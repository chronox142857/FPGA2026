#include "tft.h"
#include "board_config.h"
#include "xspi.h"
#include "xgpio.h"
#include "sleep.h"
#include <string.h>

static XSpi spi;
static XGpio gpio;
static uint32_t control=7;
static uint16_t shadow[128*128];
static int first_frame=1;
static void pins(uint32_t v){control=v;XGpio_DiscreteWrite(&gpio,1,v);}
/* Raw responses retained for debugger inspection; no assumed panel ID. */
volatile uint32_t tft_diag_flags;
volatile uint32_t tft_diag_raw[8];
#define BB_MODE 8u
#define BB_CLK 16u
#define BB_DATA 32u
#define BB_HIZ 64u
#define BB_CS 128u
static uint32_t probe_read(uint8_t command) {
    uint32_t saved=control&7u,v=(saved&~1u)|BB_MODE,raw=0;
    unsigned bit;
    pins(v|BB_CS);usleep(5);
    pins(v);usleep(5);
    for(bit=0;bit<8;bit++) {
        v=(v&~BB_DATA)|((command&(0x80u>>bit))?BB_DATA:0u);
        pins(v);usleep(2);pins(v|BB_CLK);usleep(2);
        if(bit==7) {
            /* Release SDA while SCK is still high, before the last falling
             * command edge, as required by ST7735S section 9.4.2. */
            v=(v&~BB_DATA)|BB_HIZ|1u;
            pins(v|BB_CLK);usleep(2);
        }
        pins(v);usleep(2);
    }
    /* Capture the raw stream, including any command-specific dummy bits.
     * Different read registers have different dummy lengths; decode off-board. */
    for(bit=0;bit<32;bit++) {
        pins(v|BB_CLK);usleep(2);
        raw=(raw<<1)|(XGpio_DiscreteRead(&gpio,2)&1u);
        pins(v);usleep(2);
    }
    pins(v|BB_CS);usleep(5);pins(saved);
    return raw;
}
void tft_probe(void) {
    static const uint8_t commands[8]={0x04,0xda,0xdb,0xdc,0x0a,0x0b,0x0c,0x09};
    uint32_t saved=control&7u,v=saved|BB_MODE|BB_CS,flags=0;
    unsigned i;
    /* CS remains high: verify pad low/high readback without talking to panel. */
    pins(v);usleep(5);flags|=XGpio_DiscreteRead(&gpio,2)&1u;
    pins(v|BB_DATA);usleep(5);flags|=(XGpio_DiscreteRead(&gpio,2)&1u)<<1;
    pins(v|BB_HIZ);usleep(5);flags|=(XGpio_DiscreteRead(&gpio,2)&1u)<<2;
    pins(saved);
    tft_diag_flags=0x53500000u|flags;
    for(i=0;i<8;i++)tft_diag_raw[i]=probe_read(commands[i]);
    tft_diag_flags|=0x100u;
}
static int send(const uint8_t *p,unsigned n,int data) {
#if TFT_SOFTWARE_SPI
    uint32_t v=(control&6u)|(data?1u:0u)|BB_MODE;
    unsigned i,bit;
    /* CS high and SCK low before selecting the panel. Data changes only
     * while SCK is low; the panel samples each MSB-first bit on rising SCK.
     * These conservative waits give <=125 kHz, before GPIO/loop overhead. */
    pins(v|BB_CS);usleep(2);pins(v);usleep(2);
    for(i=0;i<n;i++) {
        for(bit=0;bit<8;bit++) {
            v=(v&~BB_DATA)|((p[i]&(0x80u>>bit))?BB_DATA:0u);
            pins(v);usleep(2);
            pins(v|BB_CLK);usleep(2);
            pins(v);usleep(2);
        }
    }
    pins(v|BB_CS);usleep(2);
    return 0;
#else
    int s;
    pins(data?(control|1u):(control&~1u));
    XSpi_SetSlaveSelect(&spi,1);
    s=XSpi_Transfer(&spi,(uint8_t *)p,0,n);
    XSpi_SetSlaveSelect(&spi,0);
    return s;
#endif
}
static int cmd(uint8_t c,const uint8_t *args,unsigned n) {
    int s=send(&c,1,0);return s?s:(n?send(args,n,1):0);
}
static int window(unsigned x0,unsigned y0,unsigned x1,unsigned y1) {
    uint8_t p[4];int s;
    x0+=TFT_X_OFFSET;x1+=TFT_X_OFFSET;y0+=TFT_Y_OFFSET;y1+=TFT_Y_OFFSET;
    p[0]=(uint8_t)(x0>>8);p[1]=(uint8_t)x0;p[2]=(uint8_t)(x1>>8);p[3]=(uint8_t)x1;
    s=cmd(0x2a,p,4);if(s)return s;
    p[0]=(uint8_t)(y0>>8);p[1]=(uint8_t)y0;p[2]=(uint8_t)(y1>>8);p[3]=(uint8_t)y1;
    s=cmd(0x2b,p,4);return s?s:cmd(0x2c,0,0);
}
int tft_init(void) {
    static const uint8_t fr[]={1,0x2c,0x2d}, pw1[]={0xa2,2,0x84},pw2[]={0xc5},pw3[]={0x0a,0},pw4[]={0x8a,0x2a},vm[]={0x0e};
    static const uint8_t gp[]={0x0f,0x1a,0x0f,0x18,0x2f,0x28,0x20,0x22,0x1f,0x1b,0x23,0x37,0,7,2,0x10};
    static const uint8_t gn[]={0x0f,0x1b,0x0f,0x17,0x33,0x2c,0x29,0x2e,0x30,0x30,0x39,0x3f,0,7,3,0x10};
#if TFT_INIT_PROFILE == 1
    /* Register values/sequencing reference: Waveshare official
     * 1.44inch-LCD-HAT-Code, LCD_1in44.c (2023-06-05).
     * https://www.waveshare.com/wiki/1.44inch_LCD_HAT */
    static const uint8_t fr_partial[]={1,0x2c,0x2d,1,0x2c,0x2d};
    static const uint8_t pw_partial[]={0x8a,0xee};
    uint8_t inversion=7,test_enable=1,ram_save=0;
#endif
    uint8_t a=5,b=TFT_MADCTL;int s;
    XSpi_Config *cfg=XSpi_LookupConfig(LA_SPI_DEVICE_ID);
    if(!cfg)return -1;
    s=XSpi_CfgInitialize(&spi,cfg,cfg->BaseAddress);if(s)return s;
    s=XSpi_SetOptions(&spi,XSP_MASTER_OPTION|XSP_MANUAL_SSELECT_OPTION);if(s)return s;
    XSpi_Start(&spi);XSpi_IntrGlobalDisable(&spi);
    s=XGpio_Initialize(&gpio,LA_GPIO_DEVICE_ID);if(s)return s;
    XGpio_SetDataDirection(&gpio,1,0);XGpio_SetDataDirection(&gpio,2,0xffffffffu);
#if TFT_INIT_PROFILE == 1
    pins(2);usleep(100000);pins(0);usleep(100000);pins(2);usleep(100000);
#else
    pins(0);usleep(20000);pins(2);usleep(120000);
#endif
#define COMMAND(c,p,n) do{s=cmd(c,p,n);if(s)return s;}while(0)
#if TFT_INIT_PROFILE == 0
    COMMAND(0x01,0,0);usleep(150000);COMMAND(0x11,0,0);usleep(120000);
#endif
    COMMAND(0xb1,fr,3);COMMAND(0xb2,fr,3);
#if TFT_INIT_PROFILE == 1
    COMMAND(0xb3,fr_partial,6);COMMAND(0xb4,&inversion,1);
#endif
    COMMAND(0xc0,pw1,3);COMMAND(0xc1,pw2,1);
    COMMAND(0xc2,pw3,2);COMMAND(0xc3,pw4,2);
#if TFT_INIT_PROFILE == 1
    COMMAND(0xc4,pw_partial,2);
#endif
    COMMAND(0xc5,vm,1);
#if TFT_INIT_PROFILE == 1
    COMMAND(0xe0,gp,16);COMMAND(0xe1,gn,16);
    COMMAND(0xf0,&test_enable,1);COMMAND(0xf6,&ram_save,1);
    COMMAND(0x3a,&a,1);COMMAND(0x36,&b,1);usleep(100000);
    COMMAND(0x11,0,0);usleep(120000);COMMAND(0x29,0,0);usleep(20000);
#else
    COMMAND(0x3a,&a,1);COMMAND(0x36,&b,1);COMMAND(0xe0,gp,16);COMMAND(0xe1,gn,16);
    COMMAND(TFT_INVERT?0x21:0x20,0,0);COMMAND(0x13,0,0);COMMAND(0x29,0,0);usleep(20000);
#endif
#undef COMMAND
    pins(control|4u);first_frame=1;return 0;
}
int tft_present(const uint16_t *pixels,int force) {
    unsigned y;uint8_t row[256];int s;
    for(y=0;y<128;y++) {
        unsigned x,left=0,right=127,n=0;
        if(!force && !first_frame) {
            while(left<128 && shadow[y*128+left]==pixels[y*128+left])left++;
            if(left==128)continue;
            while(right>left && shadow[y*128+right]==pixels[y*128+right])right--;
        }
        s=window(left,y,right,y);if(s)return s;
        for(x=left;x<=right;x++){uint16_t v=pixels[y*128+x];row[n++]=(uint8_t)(v>>8);row[n++]=(uint8_t)v;}
        s=send(row,n,1);if(s)return s;
        memcpy(&shadow[y*128+left],&pixels[y*128+left],(right-left+1)*sizeof(uint16_t));
    }
    first_frame=0;return 0;
}
int tft_color_test(void) {
    static const uint16_t colors[]={0xf800,0x07e0,0x001f,0xffff};
    unsigned y,x;uint8_t row[256];int s;
    for(y=0;y<128;y++) {
        s=window(0,y,127,y);if(s)return s;
        for(x=0;x<128;x++){uint16_t c=colors[x/32];row[x*2]=(uint8_t)(c>>8);row[x*2+1]=(uint8_t)c;}
        s=send(row,256,1);if(s)return s;
    }
    first_frame=1;return 0;
}
