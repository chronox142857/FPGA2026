#ifndef TFT_H
#define TFT_H
#include <stdint.h>
int tft_init(void);
void tft_probe(void);
extern volatile uint32_t tft_diag_flags;
extern volatile uint32_t tft_diag_raw[8];
int tft_present(const uint16_t *pixels,int force);
int tft_color_test(void);
#endif
