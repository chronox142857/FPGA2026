/* Execute the production ARM renderer/transport on the host. Its recorded
 * MMIO transactions are replayed by tb_display through AXI and physical SPI. */
#include "la.h"
#include "ui.h"
#include "tft.h"
#include "board_config.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(c) do{if(!(c)){fprintf(stderr,"display host check failed at %d: %s\n",__LINE__,#c);exit(1);}}while(0)
static FILE *trace;
static uint32_t frames,host_status=1,host_id=0x4c440101u;
static unsigned writes,waits;
static uint8_t samples[LA_DEPTH];
uint32_t Xil_In32(uint32_t address) {
    switch(address-LA_DISPLAY_BASE) {
        case 0:return host_id;
        case 4:return host_status;
        case 0x0c:return frames;
        case 0x20:return 2;
        case 0x24:return 0x00800080u;
        default:return 0;
    }
}
void Xil_Out32(uint32_t address,uint32_t value) {
    uint32_t offset=address-LA_DISPLAY_BASE;
    CHECK(offset<65536 && !(offset&3));
    if(trace)fprintf(trace,"%08x %08x\n",offset,value);
    writes++;
    if(offset==8 && value==1)frames++;
}
void usleep(unsigned usec){CHECK(usec==1000);waits++;}
static void expected(unsigned page) {
    char path[80];FILE *f;unsigned i;
    snprintf(path,sizeof(path),"display_expected_%u.hex",page);
    f=fopen(path,"w");CHECK(f);
    for(i=0;i<128*128;i++)fprintf(f,"%04x\n",ui_pixels[i]);
    fclose(f);fprintf(trace,"ffffffff %08x\n",page);
}
int main(void) {
    FILE *input;unsigned n=0,value,page,previous;
    app_config cfg;ui_state ui;la_record record;la_result result;la_decoded decoded;
    host_id=0;CHECK(tft_init()==-3);host_id=0x4c440101u;
    host_status=0;CHECK(tft_init()==-1 && waits==3000);
    host_status=5;CHECK(tft_init()==-2);host_status=1;
    trace=fopen("display_mmio.hex","w");CHECK(trace);CHECK(tft_init()==0);
    input=fopen("loop_uart.hex","r");CHECK(input);
    while(fscanf(input,"%x",&value)==1){CHECK(n<LA_DEPTH);samples[n++]=(uint8_t)value;}
    fclose(input);CHECK(n==LA_DEPTH);
    memset(&record,0,sizeof(record));record.samples=samples;record.count=n;
    record.sample_hz=5000000;record.channel_mask=1;record.trigger_index=n/4;
    ui_defaults(&cfg,&ui);cfg.decode.candidate_mask=1;
    la_identify(&record,&cfg.decode,&result);
    CHECK(result.status==LA_CERTAIN && result.candidates[0].protocol==LA_UART);
    la_decode_candidate(&record,&result.candidates[0],&decoded);ui.event_total=decoded.event_count;
    for(page=0;page<4;page++) {
        ui.page=(uint8_t)page;ui_render(&ui,&cfg,&record,&result,&decoded,3);
        CHECK(tft_present(ui_pixels,0)==0);expected(page);
        previous=writes;CHECK(tft_present(ui_pixels,0)==0 && writes==previous);
    }
    /* Dirty odd pixel must preserve its even neighbour in a packed word. */
    ui_pixels[2*128+5]^=0xffffu;CHECK(tft_present(ui_pixels,0)==0);expected(4);
    CHECK(frames==5);CHECK(tft_present(NULL,0)==-5);
    fclose(trace);trace=NULL;
    puts("PASS production UI/transport: four real-UART pages, unchanged frame skip, odd-pixel dirty update and timeouts");
    return 0;
}
