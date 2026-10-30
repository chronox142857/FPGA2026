/* Host-only GPIO recorder. Executes the archived C initializer, no hardware. */
#include <stdio.h>
#include <stdlib.h>
#include "tft.h"
#include "xspi.h"
#include "xgpio.h"
static unsigned previous=128, bits, value, count, dc;
XSpi_Config *XSpi_LookupConfig(unsigned n){static XSpi_Config c={0};(void)n;return &c;}
int XSpi_CfgInitialize(XSpi *p,XSpi_Config *c,unsigned a){(void)p;(void)c;(void)a;return 0;}
int XSpi_SetOptions(XSpi *p,unsigned n){(void)p;(void)n;return 0;}
void XSpi_Start(XSpi *p){(void)p;}
void XSpi_IntrGlobalDisable(XSpi *p){(void)p;}
int XSpi_SetSlaveSelect(XSpi *p,unsigned n){(void)p;(void)n;return 0;}
int XSpi_Transfer(XSpi *p,uint8_t *a,uint8_t *b,unsigned n){(void)p;(void)a;(void)b;(void)n;abort();}
int XGpio_Initialize(XGpio *p,unsigned n){(void)p;(void)n;return 0;}
void XGpio_SetDataDirection(XGpio *p,unsigned n,uint32_t v){(void)p;(void)n;(void)v;}
uint32_t XGpio_DiscreteRead(XGpio *p,unsigned n){(void)p;(void)n;abort();}
void usleep(unsigned n){if(n>=1000)printf("D %u\n",n);}
void XGpio_DiscreteWrite(XGpio *p,unsigned n,uint32_t v){
    (void)p;(void)n;
    /* Only software-SPI mode drives these serial GPIO bits. */
    if(v&8){
        if((previous&128) && !(v&128)){bits=0;count=0;value=0;dc=v&1;}
        if(!(v&128) && !(previous&16) && (v&16)){
            if((v&1)!=dc)abort();
            value=(value<<1)|((v>>5)&1);
            if(++bits==8){printf("B %03x\n",(dc<<8)|value);count++;bits=0;value=0;}
        }
        if((previous&8) && !(previous&128) && (v&128)){if(bits)abort();printf("P %u\n",count);}
    }
    previous=v;
}
int main(void){return tft_init();}
