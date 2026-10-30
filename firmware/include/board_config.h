#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
/* Must match scripts/create_project.tcl and the unchanged, verified J3 wiring. */
#define LA_CTRL_BASE 0x43c00000u
#define LA_RAM_BASE  0x42000000u
#define LA_UART_BASE 0x40600000u
#define LA_DISPLAY_BASE 0x44a00000u
/* PL owns ST7735S initialization and SPI: profile 2, offset 2/3, MADCTL C8,
 * reset 100ms, recovery 150ms, Sleep Out wait 150ms, 250kHz byte transfers. */
#endif
