/* Runs the unchanged bsp_lcd.c on the host and records actual GPIO protocol. */
#include <stdio.h>
#include <stdlib.h>
#include "bsp_lcd.h"
const unsigned char ASCII[96*16]={0}; /* font routines are not invoked */
static unsigned pins_b, bit_count, shift_byte, byte_dc;
static unsigned bytes, falling_edges;
void HAL_Delay(uint32_t ms){printf("D %u\n",(unsigned)ms);}
void HAL_GPIO_WritePin(unsigned port,unsigned mask,unsigned level){
    if(port==GPIOC && mask==GPIO_PIN_9){printf("R %u\n",level);return;}
    if(port==GPIOA && mask==GPIO_PIN_6){printf("L %u\n",level);return;}
    if(port==GPIOB){
        unsigned previous=pins_b;
        pins_b=(pins_b&~mask)|(level?mask:0);
        if(mask==GPIO_PIN_13 && !(pins_b&GPIO_PIN_12)){
            if(!(previous&GPIO_PIN_13) && (pins_b&GPIO_PIN_13)){
                if(bit_count==0)byte_dc=!!(pins_b&GPIO_PIN_14);
                if(byte_dc!=!!(pins_b&GPIO_PIN_14))abort();
                shift_byte=(shift_byte<<1)|!!(pins_b&GPIO_PIN_15);
                bit_count++;
            }
            if((previous&GPIO_PIN_13) && !(pins_b&GPIO_PIN_13))falling_edges++;
        }
        if(!(previous&GPIO_PIN_12) && (pins_b&GPIO_PIN_12)){
            if(bit_count!=8 || !(pins_b&GPIO_PIN_13))abort();
            if(falling_edges!=(bytes==0?7u:8u))abort();
            printf("B %03x\n",(byte_dc<<8)|shift_byte);
            bytes++;bit_count=shift_byte=falling_edges=0;
        }
    }
}
int main(void){LCD_Init();LCD_BL_ON;Full_Display_Color(RED);return 0;}
