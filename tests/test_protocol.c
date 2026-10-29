#include "la.h"
#include "ui.h"
#include "la_regs.h"
#include "tinyfmt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(x) do {if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}} while(0)
static uint8_t wave[262144];
static la_record rec={wave,0,5000000,0,0,0,255};
static la_options opt;
static la_decoded dec;
static la_result result;
static unsigned tests;
static void hold(unsigned v,unsigned duration) {
    CHECK(rec.count+duration<sizeof(wave));memset(wave+rec.count,v,duration);rec.count+=duration;
}
static void reset(uint32_t fs){rec.count=0;rec.sample_hz=fs;rec.channel_mask=255;memset(&opt,0,sizeof(opt));opt.spi_mode=-1;}
static void uart(uint32_t baud,unsigned frames,int bad_stop) {
    uint32_t t,n=(uint32_t)((uint64_t)frames*12*rec.sample_hz/baud);
    hold(255,31);
    for(t=0;t<n;t++) {
        unsigned slot=(unsigned)((uint64_t)t*baud/rec.sample_hz),frame=slot/12,b=slot%12;
        unsigned data=(frame*37+0x55)&255,line=1;
        if(b==2)line=0;
        else if(b>=3 && b<=10)line=(data>>(b-3))&1;
        else if(b==11 && bad_stop)line=0;
        hold(254|line,1);
    }
    hold(255,31);
}
static void i2c_bit(unsigned sda,unsigned half) {hold(0xfc|(sda<<1),half);hold(0xfd|(sda<<1),half);}
static void i2c_start(unsigned half,int repeated) {
    if(repeated){hold(0xfe,half);hold(0xff,half);}
    else hold(255,half*2);
    hold(0xfd,half);
}
static void i2c_byte(unsigned v,unsigned ack,unsigned half) {
    unsigned b;for(b=0;b<8;b++)i2c_bit((v>>(7-b))&1,half);i2c_bit(ack,half);
}
static void i2c_stop(unsigned half){hold(0xfc,half);hold(0xfd,half);hold(0xff,half*2);}
static void i2c(unsigned hz) {
    unsigned h=rec.sample_hz/(2*hz);
    i2c_start(h,0);i2c_byte(0xa0,0,h);i2c_byte(0x3c,0,h);
    i2c_start(h,1);i2c_byte(0xa1,0,h);i2c_byte(0x96,1,h);i2c_stop(h);
}
static void spi(unsigned mode,unsigned hz,unsigned bits) {
    unsigned word,b,q=rec.sample_hz/(4*hz),half=rec.sample_hz/(2*hz),cpol=mode>>1,cpha=mode&1,current=cpol;
    unsigned tx[2]={0x96,0x3c},rx[2]={0x69,0xc3};
    hold(0xf8|cpol,q*4);hold(0xf0|cpol,q);
    for(word=0;word<2;word++)for(b=0;b<(bits?bits:8);b++) {
        unsigned next=(((tx[word]>>(7-b))&1)<<1)|(((rx[word]>>(7-b))&1)<<2);
        if(!cpha)current=next|cpol;
        hold(0xf0|current,half);
        current=next|(!cpol);hold(0xf0|current,half);
        current=next|cpol;
    }
    hold(0xf0|current,q);hold(0xf8|current,q*4);
}
static void check_bytes(const unsigned *bytes,unsigned count) {
    unsigned i,n=0;
    for(i=0;i<dec.event_count;i++)if(dec.events[i].type==LA_BYTE && !(dec.events[i].flags&(LA_FRAME_ERROR|LA_TRUNCATED))) {
        CHECK(n<count);CHECK(dec.events[i].data==bytes[n]);n++;
    }
    CHECK(n==count);
}
static void protocol_tests(void) {
    static const uint32_t bauds[]={9600,19200,38400,57600,115200,230400,460800,921600,1000000};
    unsigned k,i,m;uint8_t roles[4]={0,1,2,3};
    for(k=0;k<sizeof(bauds)/sizeof(bauds[0]);k++) {
        uint32_t fs=bauds[k]<=38400?1000000:bauds[k]<=230400?5000000:50000000;
        reset(fs);uart(bauds[k],8,0);la_decode_uart(&rec,0,bauds[k],&dec);
        CHECK(dec.candidate.valid==8);CHECK(dec.candidate.errors==0);CHECK(dec.candidate.score>=90);
        for(i=0;i<8;i++)CHECK(dec.events[i].data==((i*37+0x55)&255));
        opt.candidate_mask=1;la_identify(&rec,&opt,&result);
        CHECK(result.status==LA_CERTAIN);CHECK(result.candidates[0].protocol==LA_UART);
        CHECK(abs((int)result.candidates[0].rate-(int)bauds[k])<(int)(bauds[k]/50));tests+=2;
    }
    reset(5000000);uart(115200,5,1);la_decode_uart(&rec,0,115200,&dec);
    CHECK(dec.candidate.errors>=4);CHECK(dec.candidate.score==0);tests++;
    reset(5000000);uart(115200,4,0);rec.count-=200;
    la_decode_uart(&rec,0,115200,&dec);CHECK(dec.events[dec.event_count-1].flags&LA_TRUNCATED);tests++;
    reset(50000000);uart(17123,4,0);opt.candidate_mask=1;la_identify(&rec,&opt,&result);
    CHECK(result.status==LA_CERTAIN);CHECK(abs((int)result.candidates[0].rate-17123)<100);tests++;
    for(k=0;k<3;k++) {
        static const unsigned speeds[]={100000,400000,1000000};unsigned expected[]={0xa0,0x3c,0xa1,0x96};
        reset(50000000);i2c(speeds[k]);la_decode_i2c(&rec,0,1,&dec);
        CHECK(dec.candidate.valid==4);CHECK(dec.candidate.errors==0);CHECK(dec.candidate.score==100);check_bytes(expected,4);
        CHECK(dec.events[dec.event_count-2].flags&LA_NACK);
        opt.candidate_mask=3;la_identify(&rec,&opt,&result);
        /* A periodic SCL can also form UART bytes: keep this ambiguity if present. */
        CHECK(result.status==LA_CERTAIN || result.status==LA_AMBIGUOUS);CHECK(result.candidates[0].protocol==LA_I2C);tests+=2;
    }
    reset(5000000);i2c_start(5,0);for(i=0;i<4;i++)i2c_bit(i&1,5);i2c_stop(5);
    la_decode_i2c(&rec,0,1,&dec);CHECK(dec.candidate.errors>0);CHECK(!dec.candidate.score);tests++;
    for(m=0;m<4;m++)for(k=0;k<2;k++) {
        unsigned expected[]={0x96,0x3c};unsigned hz=k?5000000:100000;
        reset(50000000);spi(m,hz,0);la_decode_spi(&rec,roles,(uint8_t)m,&dec);
        CHECK(dec.candidate.valid==2);CHECK(!dec.candidate.errors);CHECK(dec.candidate.score==97);check_bytes(expected,2);
        CHECK(dec.events[1].aux==0x69 && dec.events[2].aux==0xc3);
        opt.candidate_mask=15;la_identify(&rec,&opt,&result);CHECK(result.status==LA_AMBIGUOUS);
        CHECK(result.candidates[0].protocol==LA_SPI);tests+=2;
    }
    reset(5000000);spi(0,100000,4);la_decode_spi(&rec,roles,0,&dec);
    /* Two four-bit words without CS between them form one legal 8-bit word. */
    CHECK(dec.candidate.valid==1);CHECK(!dec.candidate.score);tests++;
    reset(5000000);spi(0,100000,0);rec.count-=100;
    la_decode_spi(&rec,roles,0,&dec);CHECK(dec.candidate.errors>0);tests++;
    reset(5000000);hold(255,2048);opt.candidate_mask=15;la_identify(&rec,&opt,&result);CHECK(result.status==LA_UNKNOWN);tests++;
    for(k=0;k<30;k++) {
        uint32_t seed=12345+k;reset(5000000);
        for(i=0;i<2048;i++){seed=seed*1664525u+1013904223u;hold(seed>>24,1);}
        opt.candidate_mask=15;la_identify(&rec,&opt,&result);CHECK(result.status==LA_UNKNOWN);tests++;
    }
    reset(1000000);uart(115200,5,0);la_decode_uart(&rec,0,115200,&dec);CHECK(!dec.candidate.score);tests++;
    opt.candidate_mask=255;la_identify(&rec,&opt,&result);CHECK(result.status==LA_UNKNOWN);tests++;
    reset(5000000);uart(115200,4,0);opt.protocol=LA_UART;opt.channels[0]=0;opt.uart_baud=115200;
    la_identify(&rec,&opt,&result);CHECK(result.status==LA_MANUAL);tests++;
    rec.sample_hz=1000000;la_identify(&rec,&opt,&result);CHECK(result.status==LA_UNKNOWN);tests++;
    printf("PASS protocol corpus: %u checks (UART, I2C, SPI, ambiguity, malformed, noise, undersampling)\n",tests);
}
static void ui_tests(const char *prefix) {
    app_config cfg;ui_state u;unsigned page;char path[512];
    char fbuf[32];int len;
    la_snprintf(fbuf,sizeof(fbuf),"%05lu %02X %s",23ul,0x55u,"OK");CHECK(!strcmp(fbuf,"00023 55 OK"));
    len=la_snprintf(fbuf,5,"%lu",4294967295ul);CHECK(len==10 && !strcmp(fbuf,"4294"));
    la_snprintf(fbuf,sizeof(fbuf),"%05d %d",-12,(-2147483647-1));CHECK(!strcmp(fbuf,"-0012 -2147483648"));
    ui_defaults(&cfg,&u);reset(5000000);uart(115200,8,0);opt.candidate_mask=1;
    la_identify(&rec,&opt,&result);la_decode_candidate(&rec,&result.candidates[0],&dec);
    for(page=0;page<4;page++) {
        FILE *f;unsigned i;u.page=(uint8_t)page;u.zoom=4;
        ui_render(&u,&cfg,&rec,&result,&dec,LA_DONE);
        snprintf(path,sizeof(path),"%s%u.ppm",prefix,page);f=fopen(path,"wb");CHECK(f!=NULL);
        fprintf(f,"P6\n128 128\n255\n");
        for(i=0;i<128*128;i++) {
            unsigned c=ui_pixels[i];fputc(((c>>11)&31)*255/31,f);fputc(((c>>5)&63)*255/63,f);fputc((c&31)*255/31,f);
        }
        fclose(f);
    }
    u.page=3;u.editing=1;u.field=7;
    for(page=0;page<200;page++){ui_short(&u,&cfg,1,&rec,&result);CHECK(cfg.decode.candidate_mask!=0);CHECK(__builtin_popcount(cfg.decode.candidate_mask)<=4);}
    ui_back(&u);CHECK(!u.editing);ui_back(&u);CHECK(u.page==0);
    puts("PASS UI render/menu checks; four preview images exported");
}
static void rtl_fixture(const char *path,unsigned expected_proto,int mode) {
    FILE *f=fopen(path,"r");unsigned v;
    CHECK(f!=NULL);reset(5000000);
    while(fscanf(f,"%x",&v)==1)hold(v,1);fclose(f);CHECK(rec.count==LA_DEPTH);
    if(expected_proto==LA_UART && mode==1) {
        la_decode_uart(&rec,0,115200,&dec);CHECK(dec.candidate.errors>3);CHECK(dec.candidate.valid>20);
        printf("PASS RTL UART error injection: %lu frame errors detected\n",(unsigned long)dec.candidate.errors);return;
    }
    opt.candidate_mask=expected_proto==LA_UART?1:expected_proto==LA_I2C?3:15;
    la_identify(&rec,&opt,&result);
    printf("RTL fixture %s: status=%u candidates=%u protocol=%s rate=%lu\n",path,result.status,result.candidate_count,
        result.candidate_count?la_protocol_name(result.candidates[0].protocol):"UNKNOWN",result.candidate_count?(unsigned long)result.candidates[0].rate:0);
    CHECK(result.candidate_count>0);CHECK(result.candidates[0].protocol==expected_proto);
    if(expected_proto==LA_SPI) {
        unsigned i;uint8_t roles[4]={0,1,2,3};la_decode_spi(&rec,roles,(uint8_t)mode,&dec);
        CHECK(dec.candidate.valid>20);CHECK(dec.candidate.score>0);CHECK(result.status==LA_AMBIGUOUS);
        for(i=0;i<dec.event_count;i++)if(dec.events[i].type==LA_BYTE && !dec.events[i].flags)
            CHECK((dec.events[i].data ^ dec.events[i].aux)==255);
    } else {
        unsigned i,previous=0,seen=0;
        la_decode_candidate(&rec,&result.candidates[0],&dec);CHECK(dec.candidate.valid>5);
        for(i=0;i<dec.event_count;i++)if(dec.events[i].type==LA_BYTE && !(dec.events[i].flags&(LA_FRAME_ERROR|LA_TRUNCATED))) {
            if(expected_proto==LA_UART){
                if(seen && ((dec.events[i].data-previous)&255)!=0x13)
                    fprintf(stderr,"UART sequence sample=%lu prev=%02X current=%02X\n",(unsigned long)dec.events[i].sample,previous,dec.events[i].data);
                if(seen)CHECK(((dec.events[i].data-previous)&255)==0x13);
                previous=dec.events[i].data;seen=1;
            }
            else if(dec.events[i].flags&LA_ADDRESS)CHECK(dec.events[i].data==0xa0);
        }
    }
}
int main(int argc,char **argv) {
    if(argc==5 && !strcmp(argv[1],"--rtl")){rtl_fixture(argv[2],(unsigned)atoi(argv[3]),atoi(argv[4]));return 0;}
    protocol_tests();
    if(argc==3 && !strcmp(argv[1],"--ui"))ui_tests(argv[2]);
    return 0;
}
