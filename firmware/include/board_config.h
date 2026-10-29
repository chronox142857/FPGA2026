#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
/* Must match scripts/create_project.tcl; see docs/HARDWARE.md before wiring. */
#define LA_CTRL_BASE 0x43c00000u
#define LA_RAM_BASE  0x42000000u
#define LA_UART_BASE 0x40600000u
#define LA_SPI_DEVICE_ID 0u
#define LA_GPIO_DEVICE_ID 0u
/* ST7735 128x128 provisional panel profile. Not an identification of your panel. */
#define TFT_X_OFFSET 2u
#define TFT_Y_OFFSET 3u
#define TFT_MADCTL 0xc8u
#define TFT_INVERT 0u
#endif
