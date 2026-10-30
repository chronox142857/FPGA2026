#include "la.h"
#include "la_regs.h"
#include "board_config.h"
#include "ui.h"
#include "tft.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xuartlite_l.h"
#include "xtime_l.h"
#include "sleep.h"
#include <string.h>

static uint8_t samples[LA_DEPTH];
static la_record record;
static la_result result;
static la_decoded decoded;
static app_config config;
static la_options acquired_options;
static ui_state ui;
static int awaiting,screen_ok;
static uint64_t repeat_at,last_paint;
static unsigned state;
static uint32_t rd(unsigned off){return Xil_In32(LA_CTRL_BASE+off);}
static void wr(unsigned off,uint32_t v){Xil_Out32(LA_CTRL_BASE+off,v);}
static uint64_t now_ms(void){XTime t;XTime_GetTime(&t);return (uint64_t)t/(COUNTS_PER_SECOND/1000u);}
static uint64_t read64(unsigned lo,unsigned hi){return (uint64_t)rd(lo)|((uint64_t)rd(hi)<<32);}
static void dump(void) {
    uint32_t i;
    xil_printf("CAPTURE FS=%lu COUNT=%lu MASK=%02x TRIGGER=%lu\r\n",(unsigned long)record.sample_hz,
        (unsigned long)record.count,record.channel_mask,(unsigned long)record.trigger_index);
    xil_printf("TICKS FIRST=%08lx%08lx TRIGGER=%08lx%08lx\r\n",(unsigned long)(record.first_tick>>32),
        (unsigned long)record.first_tick,(unsigned long)(record.trigger_tick>>32),(unsigned long)record.trigger_tick);
    for(i=0;i<record.count;i++){xil_printf("%02x",samples[i]);if((i&31u)==31u)xil_printf("\r\n");}
    xil_printf("\r\nEND\r\n");
}
static void choose(void) {
    memset(&decoded,0,sizeof(decoded));
    if(ui.candidate>=result.candidate_count)ui.candidate=0;
    if(result.candidate_count)la_decode_candidate(&record,&result.candidates[ui.candidate],&decoded);
    ui.event_total=decoded.event_count;
}
static void completed(void) {
    uint32_t i,start=rd(LA_START_INDEX),previous=0xffffffffu,word=0;
    record.count=rd(LA_VALID_COUNT);if(record.count>LA_DEPTH)record.count=LA_DEPTH;
    record.channel_mask=(uint8_t)rd(LA_ACTIVE_MASK);
    i=rd(LA_ACTIVE_DIV);if(!i){xil_printf("Invalid divider\r\n");awaiting=0;return;}
    record.sample_hz=LA_MASTER_HZ/i;record.trigger_index=rd(LA_TRIGGER_INDEX);
    record.first_tick=read64(LA_FIRST_TICK_LO,LA_FIRST_TICK_HI);
    record.trigger_tick=read64(LA_TRIG_TICK_LO,LA_TRIG_TICK_HI);
    for(i=0;i<record.count;i++) {
        uint32_t physical=(start+i)&(LA_DEPTH-1),address=physical&~3u;
        if(address!=previous){word=Xil_In32(LA_RAM_BASE+address);previous=address;}
        samples[i]=(uint8_t)(word>>((physical&3u)*8));
    }
    la_identify(&record,&acquired_options,&result);ui.candidate=0;ui.event_offset=0;ui.origin=0;choose();
    xil_printf("DONE %lu samples; status=%u candidates=%u %s rate=%lu valid=%lu errors=%lu\r\n",(unsigned long)record.count,
        result.status,result.candidate_count,la_protocol_name(decoded.candidate.protocol),(unsigned long)decoded.candidate.rate,
        (unsigned long)decoded.candidate.valid,(unsigned long)decoded.candidate.errors);
    awaiting=0;repeat_at=now_ms()+1000;
}
static void stop(void){wr(LA_COMMAND,LA_CMD_CANCEL);awaiting=0;config.repeat=0;}
static void run(void) {
    unsigned retry;
    wr(LA_COMMAND,LA_CMD_CANCEL);
    for(retry=0;retry<1000 && rd(LA_STATE)!=LA_IDLE;retry++)usleep(10);
    if(retry==1000){xil_printf("CANCEL TIMEOUT\r\n");return;}
    wr(LA_CFG_MASK,config.mask);wr(LA_CFG_DIV,config.divider);
    wr(LA_CFG_TRIGGER,config.trigger|(config.trigger_channel<<4));
    wr(LA_CFG_LEVEL_MASK,config.level_mask);wr(LA_CFG_LEVEL,config.level_value);wr(LA_CFG_PRE,config.pretrigger);
    wr(LA_TEST_MODE,config.test_mode|(config.test_spi_mode<<2)|(config.test_error<<4));
    acquired_options=config.decode;wr(LA_COMMAND,LA_CMD_ARM);awaiting=1;
}
static void help(void) {
    xil_printf("Commands: run stop status dump color page 0..3 candidate N\r\n");
    xil_printf("rate 1|5|10|25|50 (MSa/s), trigger 0..3 CH, pre 0..3\r\n");
    xil_printf("mask HEX, level MASK VALUE (HEX), group HEX (max 4 bits)\r\n");
    xil_printf("proto 0..3 (AUTO UART I2C SPI), roles A B C D\r\n");
    xil_printf("baud 0|9600..1000000, mode -1..3, test 0..3 MODE [UART_ERROR], loop 0|1\r\n");
    xil_printf("Settings apply to next capture. color pauses loop for 2 seconds.\r\n");
}
static int bitcount(unsigned x){int n=0;while(x){n+=x&1;x>>=1;}return n;}
static int number(const char *s,unsigned base,int *value) {
    uint32_t v=0;int negative=0,any=0;
    if(*s=='-'){if(base!=10)return 0;negative=1;s++;}
    if(base==16 && s[0]=='0' && (s[1]=='x'||s[1]=='X'))s+=2;
    while(*s) {
        unsigned digit;
        if(*s>='0' && *s<='9')digit=(unsigned)(*s-'0');
        else if(*s>='a' && *s<='f')digit=(unsigned)(*s-'a'+10);
        else if(*s>='A' && *s<='F')digit=(unsigned)(*s-'A'+10);
        else return 0;
        if(digit>=base || v>(2147483647u-digit)/base)return 0;
        v=v*base+digit;any=1;s++;
    }
    if(!any)return 0;
    *value=negative?-(int)v:(int)v;return 1;
}
static void command(char *s) {
    char *tokens[5];unsigned n=0,base,i,a,b,c,d;int values[4]={0,0,0,0};
    char *p=strtok(s," \t");
    while(p && n<5){tokens[n++]=p;p=strtok(0," \t");}
    if(p || !n){help();return;}
    base=(!strcmp(tokens[0],"mask") || !strcmp(tokens[0],"level") || !strcmp(tokens[0],"group"))?16:10;
    for(i=1;i<n;i++)if(!number(tokens[i],base,&values[i-1])){help();return;}
    a=(unsigned)values[0];b=(unsigned)values[1];c=(unsigned)values[2];d=(unsigned)values[3];
    if(!strcmp(tokens[0],"run") && n==1)run();
    else if(!strcmp(tokens[0],"stop") && n==1)stop();
    else if(!strcmp(tokens[0],"dump") && n==1)dump();
    else if(!strcmp(tokens[0],"status") && n==1)xil_printf("HW=%u record=%lu status=%u candidates=%u\r\n",rd(LA_STATE),(unsigned long)record.count,result.status,result.candidate_count);
    else if(!strcmp(tokens[0],"color") && n==1){if(screen_ok)tft_color_test();usleep(2000000);}
    else if(!strcmp(tokens[0],"rate") && n==2 && (a==1||a==5||a==10||a==25||a==50))config.divider=(uint8_t)(50/a);
    else if(!strcmp(tokens[0],"trigger") && n==3 && a<4 && b<8){config.trigger=(uint8_t)a;config.trigger_channel=(uint8_t)b;}
    else if(!strcmp(tokens[0],"pre") && n==2 && a<4)config.pretrigger=(uint8_t)a;
    else if(!strcmp(tokens[0],"mask") && n==2 && a && a<256)config.mask=(uint8_t)a;
    else if(!strcmp(tokens[0],"level") && n==3 && a && a<256 && b<256){config.level_mask=(uint8_t)a;config.level_value=(uint8_t)b;}
    else if(!strcmp(tokens[0],"group") && n==2 && a && a<256 && bitcount(a)<=4)config.decode.candidate_mask=(uint8_t)a;
    else if(!strcmp(tokens[0],"proto") && n==2 && a<4)config.decode.protocol=(uint8_t)a;
    else if(!strcmp(tokens[0],"roles") && n==5 && a<8 && b<8 && c<8 && d<8){config.decode.channels[0]=(uint8_t)a;config.decode.channels[1]=(uint8_t)b;config.decode.channels[2]=(uint8_t)c;config.decode.channels[3]=(uint8_t)d;}
    else if(!strcmp(tokens[0],"baud") && n==2 && (!a || (a>=9600 && a<=1000000)))config.decode.uart_baud=a;
    else if(!strcmp(tokens[0],"mode") && n==2 && values[0]>=-1 && values[0]<=3)config.decode.spi_mode=(int8_t)values[0];
    else if(!strcmp(tokens[0],"test") && (n==3 || n==4) && a<4 && b<4 && c<2){config.test_mode=(uint8_t)a;config.test_spi_mode=(uint8_t)b;config.test_error=(uint8_t)c;}
    else if(!strcmp(tokens[0],"loop") && n==2 && a<2)config.repeat=(uint8_t)a;
    else if(!strcmp(tokens[0],"page") && n==2 && a<4){ui.page=(uint8_t)a;ui.editing=0;ui.field=0;}
    else if(!strcmp(tokens[0],"candidate") && n==2 && a<result.candidate_count){ui.candidate=(uint8_t)a;ui.event_offset=0;choose();}
    else {help();return;}
    xil_printf("OK\r\n");last_paint=0;
}
static void serial_poll(void) {
    static char line[96];static unsigned n,discard;unsigned limit=64;
    while(limit-- && !XUartLite_IsReceiveEmpty(LA_UART_BASE)) {
        char c=(char)XUartLite_ReadReg(LA_UART_BASE,XUL_RX_FIFO_OFFSET);
        if(c=='\n'||c=='\r'){if(n && !discard){line[n]=0;command(line);}n=0;discard=0;}
        else if(c==8 || c==127){if(n)n--;}
        else if(c>=32 && c<127 && !discard){if(n<sizeof(line)-1)line[n++]=c;else {n=0;discard=1;xil_printf("LINE TOO LONG\r\n");}}
    }
}
int main(void) {
    uint64_t pressed_at[2]={0,0};unsigned held[2]={0,0},previous_keys=0;
    Xil_DCacheDisable(); /* uncached MMIO and BRAM; no DMA/cache ownership ambiguity */
    ui_defaults(&config,&ui);record.samples=samples;
    xil_printf("\r\nFPGA2026 logic analyzer 1.0\r\n");
    if(rd(LA_ID)!=0x4c410101u){xil_printf("FPGA interface mismatch\r\n");return 1;}
    screen_ok=(tft_init()==0);
    xil_printf("TFT PL init=%d (verified ST7735S profile 2, 250kHz)\r\n",screen_ok);
    help();
    for(;;) {
        uint64_t now=now_ms();unsigned keys=rd(LA_KEYS),k;
        state=rd(LA_STATE);
        for(k=0;k<2;k++) {
            unsigned mask=1u<<k;
            if((keys&mask) && !(previous_keys&mask)){pressed_at[k]=now;held[k]=0;}
            if((keys&mask) && !held[k] && now-pressed_at[k]>=700) {
                held[k]=1;if(k==0)ui_back(&ui);else if(awaiting)stop();else run();last_paint=0;
            }
            if(!(keys&mask) && (previous_keys&mask) && !held[k]) {
                if(ui_short(&ui,&config,k,&record,&result))choose();
                last_paint=0;
            }
        }
        previous_keys=keys;serial_poll();
        state=rd(LA_STATE);
        if(awaiting && state==LA_DONE)completed();
        else if(awaiting && state==LA_ERROR){xil_printf("CONFIG ERROR: check mask/trigger/divider\r\n");awaiting=0;config.repeat=0;}
        if(!awaiting && config.repeat && now_ms()>=repeat_at)run();
        if(!last_paint || now_ms()-last_paint>=200) {
            ui_render(&ui,&config,&record,&result,&decoded,state);
            if(screen_ok && tft_present(ui_pixels,0)!=0){screen_ok=0;xil_printf("TFT transfer error\r\n");}
            last_paint=now_ms();
        }
        usleep(5000);
    }
}
