#include "tft.h"
#include "board_config.h"
#include "xil_io.h"
#include "sleep.h"
#include <string.h>

/* The verified PL driver owns all LCD pins/timings. ARM only submits pixels.
 * The second framebuffer is used for dirty bounds, never as sampled signal data. */
static uint16_t shadow[128*128];
static int first_frame=1;
static uint32_t rd(unsigned off){return Xil_In32(LA_DISPLAY_BASE+off);}
static void wr(unsigned off,uint32_t v){Xil_Out32(LA_DISPLAY_BASE+off,v);}
static int wait_ready(void) {
    unsigned tries;
    for(tries=0;tries<3000;tries++) {
        uint32_t status=rd(4);
        if(status&4u)return -2;
        if((status&3u)==1u)return 0;
        usleep(1000);
    }
    return -1;
}
int tft_init(void) {
    first_frame=1;
    if(rd(0)!=0x4c440101u || rd(0x20)!=2u || rd(0x24)!=0x00800080u)return -3;
    wr(8,2); /* clear a previous rejected host transaction */
    return wait_ready();
}
static int present(unsigned x0,unsigned y0,unsigned x1,unsigned y1) {
    uint32_t previous=rd(0x0c);
    int status;
    wr(0x10,x0);wr(0x14,y0);wr(0x18,x1);wr(0x1c,y1);wr(8,1);
    status=wait_ready();
    if(status)return status;
    return rd(0x0c)==previous+1u?0:-4;
}
int tft_present(const uint16_t *pixels,int force) {
    unsigned x,y,left=128,right=0,top=128,bottom=0;
    int status;
    if(!pixels)return -5;
    status=wait_ready();if(status)return status;
    for(y=0;y<128;y++)for(x=0;x<128;x+=2) {
        unsigned i=y*128+x;
        if(force || first_frame || pixels[i]!=shadow[i] || pixels[i+1]!=shadow[i+1]) {
            wr(0x8000+i*2,(uint32_t)pixels[i]|((uint32_t)pixels[i+1]<<16));
            if(x<left)left=x;
            if(x+1>right)right=x+1;
            if(y<top)top=y;
            bottom=y;
        }
    }
    if(left==128)return 0;
    status=present(left,top,right,bottom);
    if(status){first_frame=1;return status;}
    memcpy(shadow,pixels,sizeof(shadow));first_frame=0;return 0;
}
int tft_color_test(void) {
    static const uint16_t colors[]={0xf800,0x07e0,0x001f,0xffff};
    unsigned x,y;int status=wait_ready();if(status)return status;
    for(y=0;y<128;y++)for(x=0;x<128;x+=2) {
        uint32_t color=colors[x/32];wr(0x8000+(y*128+x)*2,color|(color<<16));
    }
    first_frame=1;
    return present(0,0,127,127);
}
