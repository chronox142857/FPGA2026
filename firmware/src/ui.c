#include "ui.h"
#include "la_regs.h"
#include <string.h>
#include "tinyfmt.h"
#define snprintf la_snprintf

uint16_t ui_pixels[UI_W*UI_H];
enum {BLACK=0x0000,WHITE=0xffff,GREY=0x8410,GREEN=0x07e0,CYAN=0x07ff,YELLOW=0xffe0,RED=0xf800,BLUE=0x001f};
static const char symbols[]="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.:/%?+=<>_";
/* Original 5x7 uppercase bitmap font, rows stored in low five bits. */
static const uint8_t glyphs[][7]={
 {14,17,19,21,25,17,14},{4,12,4,4,4,4,14},{14,17,1,2,4,8,31},{30,1,1,14,1,1,30},
 {2,6,10,18,31,2,2},{31,16,16,30,1,1,30},{14,16,16,30,17,17,14},{31,1,2,4,8,8,8},
 {14,17,17,14,17,17,14},{14,17,17,15,1,1,14},
 {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},{15,16,16,16,16,16,15},{30,17,17,17,17,17,30},
 {31,16,16,30,16,16,31},{31,16,16,30,16,16,16},{15,16,16,19,17,17,15},{17,17,17,31,17,17,17},
 {14,4,4,4,4,4,14},{7,2,2,2,2,18,12},{17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
 {17,27,21,21,17,17,17},{17,25,25,21,19,19,17},{14,17,17,17,17,17,14},{30,17,17,30,16,16,16},
 {14,17,17,17,21,18,13},{30,17,17,30,20,18,17},{15,16,16,14,1,1,30},{31,4,4,4,4,4,4},
 {17,17,17,17,17,17,14},{17,17,17,17,17,10,4},{17,17,17,21,21,27,17},{17,17,10,4,10,17,17},
 {17,17,10,4,4,4,4},{31,1,2,4,8,16,31},
 {0,0,0,31,0,0,0},{0,0,0,0,0,6,6},{0,6,6,0,6,6,0},{1,2,2,4,8,8,16},
 {25,26,2,4,8,11,19},{14,17,1,2,4,0,4},{0,4,4,31,4,4,0},{0,0,31,0,31,0,0},
 {2,4,8,16,8,4,2},{8,4,2,1,2,4,8},{0,0,0,0,0,0,31}
};
static void pixel(int x,int y,uint16_t color) {if(x>=0 && x<UI_W && y>=0 && y<UI_H)ui_pixels[y*UI_W+x]=color;}
static void line(int x0,int y0,int x1,int y1,uint16_t color) {
    int dx=x1>x0?x1-x0:x0-x1,sx=x0<x1?1:-1,dy=y1>y0?y0-y1:y1-y0,sy=y0<y1?1:-1,err=dx+dy;
    for(;;){int e;pixel(x0,y0,color);if(x0==x1 && y0==y1)break;e=2*err;if(e>=dy){err+=dy;x0+=sx;}if(e<=dx){err+=dx;y0+=sy;}}
}
static void text(int x,int y,const char *s,uint16_t color) {
    while(*s && x<UI_W-4) {
        const char *p=strchr(symbols,*s++);int row,col;
        if(p)for(row=0;row<7;row++)for(col=0;col<5;col++)if(glyphs[p-symbols][row]&(1u<<(4-col)))pixel(x+col,y+row,color);
        x+=6;
    }
}
static unsigned popcount(uint8_t v){unsigned n=0;while(v){n+=v&1u;v>>=1;}return n;}
void ui_defaults(app_config *c,ui_state *u) {
    memset(c,0,sizeof(*c));memset(u,0,sizeof(*u));c->divider=10;c->mask=255;c->level_mask=1;
    c->decode.candidate_mask=15;c->decode.spi_mode=-1;
    c->decode.channels[0]=0;c->decode.channels[1]=1;c->decode.channels[2]=2;c->decode.channels[3]=3;
    u->zoom=8;
}
static void status(const app_config *c,const la_record *r,const la_result *res,const la_decoded *d,unsigned hw) {
    char s[32];const char *names[]={"IDLE","WAIT TRIG","CAPTURING","DONE","CONFIG ERROR","FINALIZING"};
    text(0,12,hw<=5?names[hw]:"HW ERROR",hw==LA_ERROR?RED:GREEN);
    snprintf(s,sizeof(s),"RATE %luK",(unsigned long)(LA_MASTER_HZ/c->divider/1000));text(0,24,s,WHITE);
    snprintf(s,sizeof(s),"POINTS %lu",(unsigned long)r->count);text(0,36,s,WHITE);
    text(0,48,res->status==LA_UNKNOWN?"UNKNOWN":res->status==LA_AMBIGUOUS?"AMBIGUOUS":res->status==LA_MANUAL?"MANUAL":"IDENTIFIED",YELLOW);
    if(res->candidate_count) {
        snprintf(s,sizeof(s),"%s %lu",la_protocol_name(d->candidate.protocol),(unsigned long)d->candidate.rate);text(0,60,s,CYAN);
        snprintf(s,sizeof(s),"VALID %lu ERR %lu",(unsigned long)d->candidate.valid,(unsigned long)d->candidate.errors);text(0,72,s,WHITE);
        snprintf(s,sizeof(s),"CANDIDATES %u%s",res->candidate_count,res->more_candidates?"+":"");text(0,84,s,GREY);
    }
    text(0,98,c->repeat?"LOOP ON":"SINGLE SHOT",GREY);
}
static void wave(const ui_state *u,const la_record *r) {
    unsigned lane,x;uint32_t step=1u<<u->zoom;char s[32];
    if(!r->count){text(0,35,"NO CAPTURE",YELLOW);return;}
    for(lane=0;lane<4;lane++) {
        unsigned ch=lane+u->bank*4;int high=18+(int)lane*21,low=high+12;
        snprintf(s,sizeof(s),"%u",ch);text(0,high+3,s,CYAN);
        if(!(r->channel_mask&(1u<<ch))){text(20,high,"OFF",GREY);continue;}
        for(x=0;x<112;x++) {
            uint32_t a=u->origin+x*step,b=a+step,i;unsigned first,last,changed=0;
            if(a>=r->count)break;
            if(b>r->count)b=r->count;
            first=(r->samples[a]>>ch)&1u;last=first;
            if(a && (((r->samples[a-1]>>ch)&1u)!=first))changed=1;
            for(i=a+1;i<b;i++){unsigned v=(r->samples[i]>>ch)&1u;if(v!=last)changed=1;last=v;}
            pixel((int)x+16,first?high:low,GREEN);
            if(changed)line((int)x+16,high,(int)x+16,low,GREEN);
        }
    }
    if(r->trigger_index>=u->origin && r->trigger_index<u->origin+112*step)
        line(16+(int)((r->trigger_index-u->origin)/step),12,16+(int)((r->trigger_index-u->origin)/step),100,YELLOW);
    snprintf(s,sizeof(s),"%cBANK %u Z%u",u->editing && u->field==0?'>':' ',u->bank,u->zoom);text(0,102,s,WHITE);
    snprintf(s,sizeof(s),"%c< %c> %lu",u->editing && u->field==2?'>':' ',u->editing && u->field==3?'>':' ',(unsigned long)u->origin);text(0,112,s,GREY);
}
static void decoded(const ui_state *u,const la_record *r,const la_result *res,const la_decoded *d) {
    unsigned row;char s[40];
    if(!res->candidate_count){text(0,25,"NO VALID CANDIDATE",YELLOW);return;}
    snprintf(s,sizeof(s),"%s C%u/%u M%u",la_protocol_name(d->candidate.protocol),u->candidate+1,res->candidate_count,d->candidate.mode);text(0,12,s,CYAN);
    if(d->candidate.protocol==LA_UART)snprintf(s,sizeof(s),"TX %u",d->candidate.channels[0]);
    else if(d->candidate.protocol==LA_I2C)snprintf(s,sizeof(s),"SCL %u SDA %u",d->candidate.channels[0],d->candidate.channels[1]);
    else snprintf(s,sizeof(s),"CK%u TX%u RX%u CS%u",d->candidate.channels[0],d->candidate.channels[1],d->candidate.channels[2],d->candidate.channels[3]);
    text(0,22,s,GREY);
    for(row=0;row<7 && u->event_offset+row<d->event_count;row++) {
        const la_event *e=&d->events[u->event_offset+row];
        uint32_t us=r->sample_hz?(uint32_t)((uint64_t)e->sample*1000000u/r->sample_hz):0;
        if(e->type==LA_BYTE) {
            if(e->flags&LA_TRUNCATED)snprintf(s,sizeof(s),"%05lu TRUNC",(unsigned long)us);
            else if(d->candidate.protocol==LA_SPI)snprintf(s,sizeof(s),"%05lu %02X/%02X",(unsigned long)us,e->data,e->aux);
            else if(d->candidate.protocol==LA_I2C && (e->flags&LA_ADDRESS))snprintf(s,sizeof(s),"%05lu %02X %s",(unsigned long)us,e->data>>1,(e->flags&LA_READ)?"READ":"WRITE");
            else if(d->candidate.protocol==LA_I2C)snprintf(s,sizeof(s),"%05lu %02X %s",(unsigned long)us,e->data,(e->flags&LA_NACK)?"NACK":"ACK");
            else snprintf(s,sizeof(s),"%05lu %02X%s",(unsigned long)us,e->data,(e->flags&LA_FRAME_ERROR)?" ERR":"");
        } else {
            static const char *t[]={"BYTE","START","RESTART","STOP","CS ON","CS OFF"};
            snprintf(s,sizeof(s),"%05lu %s",(unsigned long)us,e->type<=5?t[e->type]:"?");
        }
        text(0,34+(int)row*10,s,(e->flags&(LA_FRAME_ERROR|LA_TRUNCATED))?RED:WHITE);
    }
    snprintf(s,sizeof(s),"%cEVENT %cCANDIDATE",u->editing && u->field==0?'>':' ',u->editing && u->field==1?'>':' ');text(0,110,s,GREY);
    if(d->dropped)text(0,120,"MORE: UART EXPORT",YELLOW);
}
static void settings(const ui_state *u,const app_config *c) {
    static const char *labels[]={"RATE K","TRIGGER","TRIG CH","PRE %","CH MASK","LEVEL MASK","LEVEL VALUE","CAND MASK","PROTOCOL","ROLE 0","ROLE 1","ROLE 2","ROLE 3","UART BAUD","SPI MODE","TEST GEN","TEST MODE","LOOP","TEST ERROR"};
    unsigned first=(u->field/8)*8,i;char s[32];
    uint32_t vals[UI_SETTINGS]={LA_MASTER_HZ/c->divider/1000,c->trigger,c->trigger_channel,c->pretrigger*25,c->mask,c->level_mask,c->level_value,
        c->decode.candidate_mask,c->decode.protocol,c->decode.channels[0],c->decode.channels[1],c->decode.channels[2],c->decode.channels[3],
        c->decode.uart_baud,(uint32_t)(c->decode.spi_mode+1),c->test_mode,c->test_spi_mode,c->repeat,c->test_error};
    for(i=first;i<first+8 && i<UI_SETTINGS;i++) {
        if(i==4 || i==5 || i==6 || i==7)snprintf(s,sizeof(s),"%c%s %02lX",i==u->field?'>':' ',labels[i],(unsigned long)vals[i]);
        else snprintf(s,sizeof(s),"%c%s %lu",i==u->field?'>':' ',labels[i],(unsigned long)vals[i]);
        text(0,16+(int)(i-first)*12,s,i==u->field?YELLOW:WHITE);
    }
    text(0,116,u->editing?"K0:NEXT K1:CHANGE":"K1:EDIT",GREY);
}
void ui_render(const ui_state *u,const app_config *c,const la_record *r,const la_result *res,const la_decoded *d,unsigned hw) {
    static const char *titles[]={"LOGIC ANALYZER","WAVEFORM","DECODE / US","SETTINGS"};
    memset(ui_pixels,0,sizeof(ui_pixels));text(0,0,titles[u->page%4],CYAN);line(0,9,127,9,BLUE);
    switch(u->page%4){case 0:status(c,r,res,d,hw);break;case 1:wave(u,r);break;case 2:decoded(u,r,res,d);break;default:settings(u,c);break;}
    if(u->page==0)text(0,119,"HOLD K1:RUN/CANCEL",GREY);
}
int ui_short(ui_state *u,app_config *c,unsigned key,const la_record *r,const la_result *res) {
    unsigned n;static const uint8_t divs[]={50,10,5,2,1};
    static const uint32_t bauds[]={0,9600,19200,38400,57600,115200,230400,460800,921600,1000000};
    if(!u->editing) {
        if(key==0){u->page=(u->page+1)%4;u->field=0;}
        else if(u->page){u->editing=1;u->field=0;}
        return 0;
    }
    if(key==0) {u->field=(u->field+1)%(u->page==1?4:u->page==2?2:UI_SETTINGS);return 0;}
    if(u->page==1) {
        if(u->field==0)u->bank^=1;
        else if(u->field==1){u->zoom=(u->zoom+1)%10;u->origin=0;}
        else if(u->field==2){uint32_t span=56u<<u->zoom;u->origin=u->origin>span?u->origin-span:0;}
        else {uint32_t step=1u<<u->zoom;u->origin+=56*step;if(u->origin>=r->count)u->origin=0;}
    } else if(u->page==2) {
        if(u->field==0){u->event_offset+=7;if(u->event_offset>=u->event_total)u->event_offset=0;}
        else if(res->candidate_count){u->candidate=(u->candidate+1)%res->candidate_count;u->event_offset=0;return 1;}
    } else if(u->page==3) switch(u->field) {
        case 0:for(n=0;n<5;n++)if(divs[n]==c->divider)break;c->divider=divs[(n+1)%5];break;
        case 1:c->trigger=(c->trigger+1)%4;break;
        case 2:c->trigger_channel=(c->trigger_channel+1)%8;break;
        case 3:c->pretrigger=(c->pretrigger+1)%4;break;
        case 4:c->mask++;if(!c->mask)c->mask=1;break;
        case 5:c->level_mask++;if(!c->level_mask)c->level_mask=1;break;
        case 6:c->level_value++;break;
        case 7:do{c->decode.candidate_mask++;}while(!c->decode.candidate_mask || popcount(c->decode.candidate_mask)>4);break;
        case 8:c->decode.protocol=(c->decode.protocol+1)%4;break;
        case 9:case 10:case 11:case 12:c->decode.channels[u->field-9]=(c->decode.channels[u->field-9]+1)%8;break;
        case 13:for(n=0;n<10;n++)if(bauds[n]==c->decode.uart_baud)break;c->decode.uart_baud=bauds[(n+1)%10];break;
        case 14:c->decode.spi_mode++;if(c->decode.spi_mode>3)c->decode.spi_mode=-1;break;
        case 15:c->test_mode=(c->test_mode+1)%4;break;
        case 16:c->test_spi_mode=(c->test_spi_mode+1)%4;break;
        case 17:c->repeat^=1;break;
        case 18:c->test_error^=1;break;
        default:break;
    }
    return 0;
}
void ui_back(ui_state *u){if(u->editing)u->editing=0;else u->page=0;}
