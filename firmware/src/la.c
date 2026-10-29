#include "la.h"
#include <string.h>
#include <limits.h>

static unsigned bit(const la_record *r, uint32_t i, unsigned ch) {
    return (r->samples[i] >> ch) & 1u;
}
static int channel_ok(const la_record *r, unsigned ch) {
    return r && r->samples && r->count && ch<8 && (r->channel_mask & (1u<<ch));
}
static void init(la_decoded *d, uint8_t proto) {
    memset(d,0,sizeof(*d)); d->candidate.protocol=proto;
    memset(d->candidate.channels,255,4);
}
static void event(la_decoded *d,uint32_t start,uint32_t end,unsigned type,unsigned flags,unsigned data,unsigned aux) {
    la_event *e;
    if(d->event_count>=LA_MAX_EVENTS) {d->dropped++;return;}
    e=&d->events[d->event_count++]; e->sample=start;e->end_sample=end;
    e->type=(uint8_t)type;e->flags=(uint8_t)flags;e->data=(uint16_t)data;e->aux=(uint16_t)aux;
}
const char *la_protocol_name(uint8_t p) {
    static const char *names[]={"AUTO","UART","I2C","SPI"};
    return p<=LA_SPI?names[p]:"?";
}
uint64_t la_sample_tick(const la_record *r,uint32_t i) {
    return r->sample_hz?r->first_tick+(uint64_t)i*(LA_MASTER_HZ/r->sample_hz):r->first_tick;
}
// Score clock alignment on complete internal runs, excluding window boundary runs.
static unsigned uart_alignment(const la_record *r,unsigned ch,uint32_t baud) {
    uint32_t i,start=0,runs=0,good=0; int seen=0;
    for(i=1;i<r->count;i++) if(bit(r,i,ch)!=bit(r,i-1,ch)) {
        if(seen) {
            uint64_t scaled=(uint64_t)(i-start)*baud;
            uint32_t n=(uint32_t)((scaled+r->sample_hz/2)/r->sample_hz);
            uint64_t expected=(uint64_t)n*r->sample_hz;
            uint64_t diff=scaled>expected?scaled-expected:expected-scaled;
            if(n && diff<=r->sample_hz/5u)good++;
            runs++;
        }
        start=i;seen=1;
    }
    return runs?good*100u/runs:0;
}
// Lock framing using three consecutive valid stop bits. A capture may begin
// inside a byte; treating its first data edge as a start creates plausible junk.
static uint32_t uart_lock(const la_record *r,unsigned ch,uint32_t baud,uint32_t from,uint32_t *first_fall) {
    uint32_t i;
    *first_fall=UINT_MAX;
    for(i=from?from:1;i<r->count;i++)if(bit(r,i-1,ch) && !bit(r,i,ch)) {
        uint32_t p=i;unsigned n;
        if(*first_fall==UINT_MAX)*first_fall=i;
        for(n=0;n<3;n++) {
            uint64_t stop=(uint64_t)p+(19ull*r->sample_hz+baud)/(2ull*baud);
            if(stop>=r->count || !bit(r,(uint32_t)stop,ch))break;
            if(n==2)return i;
            p+=(uint32_t)(10ull*r->sample_hz/baud);
            while(p<r->count && !(bit(r,p-1,ch) && !bit(r,p,ch)))p++;
            if(p>=r->count)break;
        }
    }
    return UINT_MAX;
}
void la_decode_uart(const la_record *r,uint8_t ch,uint32_t baud,la_decoded *d) {
    uint32_t i,lock,first_fall; unsigned align;
    init(d,LA_UART);d->candidate.channels[0]=ch;d->candidate.rate=baud;
    if(!channel_ok(r,ch) || baud<9600 || baud>1000000 || r->sample_hz/baud<10) return;
    first_fall=UINT_MAX;
    for(i=1;i<r->count;i++)if(bit(r,i-1,ch) && !bit(r,i,ch)){first_fall=i;break;}
    lock=1;
    // Preserve a genuine first start with a complete idle bit, including bad
    // stop bits. Only search framing when the window begins inside a frame.
    if(first_fall!=UINT_MAX && (!bit(r,0,ch) || (uint64_t)(first_fall+2)*baud<r->sample_hz)) {
        uint32_t ignored;
        lock=uart_lock(r,ch,baud,1,&ignored);
        if(lock!=UINT_MAX && first_fall<lock)event(d,0,lock-1,LA_BYTE,LA_TRUNCATED,0,0);
    }
    for(i=lock==UINT_MAX?1:lock;i<r->count;i++) if(bit(r,i-1,ch) && !bit(r,i,ch)) {
        uint32_t start=i, stop,finish;unsigned value=0,b,flags=0;
        uint64_t stop64=(uint64_t)i+(19ull*r->sample_hz+baud)/(2ull*baud);
        if(stop64>=r->count) {
            event(d,i,r->count-1,LA_BYTE,LA_TRUNCATED,0,0);break;
        }
        stop=(uint32_t)stop64;
        if(bit(r,i+r->sample_hz/(2u*baud),ch)) continue;
        for(b=0;b<8;b++) {
            uint32_t pos=i+(uint32_t)(((2ull*b+3)*r->sample_hz+baud)/(2ull*baud));
            value|=bit(r,pos,ch)<<b;
        }
        if(!bit(r,stop,ch)) {flags|=LA_FRAME_ERROR;d->candidate.errors++;}
        else d->candidate.valid++;
        finish=i+(uint32_t)((10ull*r->sample_hz)/baud);
        if(finish>=r->count)finish=r->count-1;
        event(d,start,finish,LA_BYTE,flags,value,0);
        i=finish?finish-1:finish;
    }
    align=uart_alignment(r,ch,baud);
    if(d->candidate.valid>=3 && d->candidate.valid*100u/(d->candidate.valid+d->candidate.errors)>=95 && align>=85)
        d->candidate.score=(uint8_t)(60+(d->candidate.valid>10?10:d->candidate.valid)+align/4);
}
void la_decode_i2c(const la_record *r,uint8_t scl,uint8_t sda,la_decoded *d) {
    uint32_t i,start=0,byte_start=0,previous_rise=0,period_sum=0,period_count=0,transactions=0;
    unsigned active=0,bits=0,value=0,address=1;
    init(d,LA_I2C);d->candidate.channels[0]=scl;d->candidate.channels[1]=sda;
    if(!channel_ok(r,scl) || !channel_ok(r,sda) || scl==sda) return;
    for(i=1;i<r->count;i++) {
        unsigned c=bit(r,i,scl),pc=bit(r,i-1,scl),s=bit(r,i,sda),ps=bit(r,i-1,sda);
        if(c && pc && s!=ps) {
            if(!s) {
                if(active && bits>1)d->candidate.errors++;
                event(d,i,i,active?LA_RESTART:LA_START,0,0,0);
                active=1;bits=0;value=0;address=1;start=i;previous_rise=0;
            } else if(active) {
                if(bits>1) {d->candidate.errors++;event(d,byte_start,i,LA_BYTE,LA_TRUNCATED,value,0);}
                event(d,i,i,LA_STOP,0,0,0);active=0;bits=0;transactions++;
            }
        } else if(active && !pc && c) {
            if(previous_rise && i-previous_rise<r->sample_hz/1000u) {
                period_sum+=i-previous_rise;period_count++;
            }
            previous_rise=i;
            if(bits==0)byte_start=i;
            if(bits<8) {value=(value<<1)|s;bits++;}
            else {
                unsigned flags=(s?LA_NACK:0)|(address?LA_ADDRESS:0)|((address && (value&1))?LA_READ:0);
                event(d,byte_start,i,LA_BYTE,flags,value,s);
                d->candidate.valid++;address=0;bits=0;value=0;
            }
        }
    }
    if(active) {event(d,start,r->count-1,LA_STOP,LA_TRUNCATED,0,0);d->candidate.errors++;}
    if(period_count && period_sum)d->candidate.rate=(uint32_t)((uint64_t)r->sample_hz*period_count/period_sum);
    if(transactions && d->candidate.valid>=2 && d->candidate.errors*20<=d->candidate.valid && d->candidate.rate>=1000 &&
        d->candidate.rate<=1000000 && r->sample_hz/d->candidate.rate>=10) d->candidate.score=(uint8_t)(100-(d->candidate.errors?1:0));
}
void la_decode_spi(const la_record *r,const uint8_t ch[4],uint8_t mode,la_decoded *d) {
    uint32_t i,start=0,last_sample=0,period_sum=0,period_count=0,transactions=0;
    unsigned bits=0,tx=0,rx=0,active=0,cpol=(mode>>1)&1,cpha=mode&1,idle_count=0,idle_good=0;
    init(d,LA_SPI);memcpy(d->candidate.channels,ch,4);d->candidate.mode=mode;
    if(mode>3)return;
    for(i=0;i<4;i++) {
        unsigned j;if(!channel_ok(r,ch[i]))return;
        for(j=0;j<i;j++)if(ch[j]==ch[i])return;
    }
    for(i=1;i<r->count;i++) {
        unsigned cs=bit(r,i,ch[3]),pcs=bit(r,i-1,ch[3]);
        unsigned ck=bit(r,i,ch[0]),pck=bit(r,i-1,ch[0]);
        if(cs) {idle_count++;if(ck==cpol)idle_good++;}
        if(pcs && !cs) {
            active=1;start=i;bits=0;tx=0;rx=0;last_sample=0;
            event(d,i,i,LA_SELECT,0,0,0);
        }
        if(!pcs && cs && active) {
            if(bits) {event(d,start,i,LA_BYTE,LA_TRUNCATED,tx,rx);d->candidate.errors++;}
            event(d,i,i,LA_DESELECT,0,0,0);active=0;transactions++;
        }
        if(active && !cs && ck!=pck && ((cpha==0 && ck!=cpol)||(cpha==1 && ck==cpol))) {
            if(last_sample) {period_sum+=i-last_sample;period_count++;}
            last_sample=i;
            if(!bits)start=i;
            tx=(tx<<1)|bit(r,i,ch[1]);rx=(rx<<1)|bit(r,i,ch[2]);bits++;
            if(bits==8) {event(d,start,i,LA_BYTE,0,tx,rx);d->candidate.valid++;bits=0;tx=0;rx=0;}
        }
    }
    if(active) {event(d,start,r->count-1,LA_DESELECT,LA_TRUNCATED,0,0);d->candidate.errors++;}
    if(period_count && period_sum)d->candidate.rate=(uint32_t)((uint64_t)r->sample_hz*period_count/period_sum);
    if(transactions && d->candidate.valid>=2 && d->candidate.errors*20<=d->candidate.valid && idle_count && idle_good*100u/idle_count>=95 &&
        d->candidate.rate && d->candidate.rate<=5000000 && r->sample_hz/d->candidate.rate>=10)d->candidate.score=(uint8_t)(97-(d->candidate.errors?1:0));
}
void la_decode_candidate(const la_record *r,const la_candidate *c,la_decoded *d) {
    switch(c->protocol) {
        case LA_UART:la_decode_uart(r,c->channels[0],c->rate,d);break;
        case LA_I2C:la_decode_i2c(r,c->channels[0],c->channels[1],d);break;
        case LA_SPI:la_decode_spi(r,c->channels,c->mode,d);break;
        default:init(d,LA_AUTO);break;
    }
}
static void add(la_result *out,const la_candidate *c) {
    unsigned i,j;
    if(!c->score)return;
    for(i=0;i<out->candidate_count;i++) {
        la_candidate *p=&out->candidates[i];
        if(p->protocol==c->protocol && p->mode==c->mode && !memcmp(p->channels,c->channels,4) && p->rate==c->rate)return;
    }
    i=out->candidate_count;
    if(i==LA_MAX_CANDIDATES) {out->more_candidates=1;if(c->score<=out->candidates[i-1].score)return;i--;}
    else out->candidate_count++;
    while(i && out->candidates[i-1].score<c->score) {out->candidates[i]=out->candidates[i-1];i--;}
    out->candidates[i]=*c;
    // Remove weak alternatives after a strongly framed protocol is found.
    for(j=0;j<out->candidate_count;j++) if(out->candidates[j].score+10<out->candidates[0].score) {
        out->candidate_count=(uint8_t)j;break;
    }
}
static void estimate_uart(const la_record *r,uint8_t ch,la_candidate *best) {
    static const uint32_t rates[]={9600,19200,38400,57600,115200,230400,460800,921600,1000000};
    la_decoded d;uint32_t i,start=0,minrun=UINT_MAX;unsigned seen=0,k;
    memset(best,0,sizeof(*best));
    for(i=1;i<r->count;i++)if(bit(r,i,ch)!=bit(r,i-1,ch)) {
        if(seen && i-start<minrun)minrun=i-start;
        start=i;seen=1;
    }
    for(k=0;k<sizeof(rates)/sizeof(rates[0]);k++) {
        la_decode_uart(r,ch,rates[k],&d);if(d.candidate.score>best->score)*best=d.candidate;
    }
    if(minrun && minrun!=UINT_MAX)for(k=1;k<=9;k++) {
        uint32_t baud=(uint32_t)(((uint64_t)r->sample_hz*k+minrun/2)/minrun);
        if(baud<9600 || baud>1000000)continue;
        la_decode_uart(r,ch,baud,&d);if(d.candidate.score>best->score)*best=d.candidate;
    }
}
void la_identify(const la_record *r,const la_options *o,la_result *out) {
    uint8_t ch[4];unsigned n=0,a,b,c,e,m;la_decoded d;la_candidate best;
    memset(out,0,sizeof(*out));
    if(!r || !r->samples || !r->count || !r->sample_hz || !o)return;
    for(a=0;a<8;a++)if((o->candidate_mask & r->channel_mask) & (1u<<a)) {
        if(n==4)return;
        ch[n++]=(uint8_t)a;
    }
    if(o->protocol!=LA_AUTO) {
        if(o->protocol==LA_UART) {
            if(!channel_ok(r,o->channels[0]) || (o->uart_baud &&
                (o->uart_baud<9600 || o->uart_baud>1000000 || r->sample_hz/o->uart_baud<10)))return;
            if(o->uart_baud) {la_decode_uart(r,o->channels[0],o->uart_baud,&d);best=d.candidate;}
            else if(channel_ok(r,o->channels[0]))estimate_uart(r,o->channels[0],&best);else return;
            if(!o->uart_baud && !best.score)return;
            out->candidates[0]=best;out->candidate_count=1;out->status=LA_MANUAL;return;
        }
        if(o->protocol==LA_I2C) {
            la_decode_i2c(r,o->channels[0],o->channels[1],&d);
            if(!d.candidate.rate || d.candidate.rate>1000000 || r->sample_hz/d.candidate.rate<10)return;
            out->candidates[0]=d.candidate;
            out->candidate_count=1;out->status=LA_MANUAL;return;
        }
        if(o->protocol==LA_SPI) {
            if(o->spi_mode>=0 && o->spi_mode<=3) {
                la_decode_spi(r,o->channels,(uint8_t)o->spi_mode,&d);
                if(!d.candidate.rate || d.candidate.rate>5000000 || r->sample_hz/d.candidate.rate<10)return;
                out->candidates[0]=d.candidate;
                out->candidate_count=1;out->status=LA_MANUAL;return;
            }
            for(m=0;m<4;m++){la_decode_spi(r,o->channels,(uint8_t)m,&d);add(out,&d.candidate);}
        }
    } else {
        for(a=0;a<n;a++) {estimate_uart(r,ch[a],&best);add(out,&best);}
        for(a=0;a<n;a++)for(b=0;b<n;b++)if(a!=b) {
            la_decode_i2c(r,ch[a],ch[b],&d);add(out,&d.candidate);
        }
        if(n==4)for(a=0;a<4;a++)for(b=0;b<4;b++)for(c=0;c<4;c++)for(e=0;e<4;e++)
            if(a!=b && a!=c && a!=e && b!=c && b!=e && c!=e) {
                uint8_t roles[4]={ch[a],ch[b],ch[c],ch[e]};
                for(m=0;m<4;m++) {la_decode_spi(r,roles,(uint8_t)m,&d);add(out,&d.candidate);}
            }
    }
    if(out->candidate_count)out->status=(out->candidate_count>1 || out->candidates[0].protocol==LA_SPI)?LA_AMBIGUOUS:LA_CERTAIN;
}
