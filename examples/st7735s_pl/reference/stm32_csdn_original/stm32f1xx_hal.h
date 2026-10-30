/* Host recorder declarations only, not the STM32 HAL library. */
#ifndef HOST_LCD_HAL_H
#define HOST_LCD_HAL_H
#include <stdint.h>
#define GPIOA 0u
#define GPIOB 1u
#define GPIOC 2u
#define GPIO_PIN_6 (1u<<6)
#define GPIO_PIN_9 (1u<<9)
#define GPIO_PIN_12 (1u<<12)
#define GPIO_PIN_13 (1u<<13)
#define GPIO_PIN_14 (1u<<14)
#define GPIO_PIN_15 (1u<<15)
#define GPIO_PIN_RESET 0u
#define GPIO_PIN_SET 1u
void HAL_GPIO_WritePin(unsigned port,unsigned pins,unsigned level);
void HAL_Delay(uint32_t ms);
#endif
