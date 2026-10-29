#ifndef TFT_H
#define TFT_H
#include <stdint.h>
int tft_init(void);
int tft_present(const uint16_t *pixels,int force);
int tft_color_test(void);
#endif
