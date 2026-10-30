#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
/* Must match scripts/create_project.tcl; see docs/HARDWARE.md before wiring. */
#define LA_CTRL_BASE 0x43c00000u
#define LA_RAM_BASE  0x42000000u
#define LA_UART_BASE 0x40600000u
#define LA_SPI_DEVICE_ID 0u
#define LA_GPIO_DEVICE_ID 0u
/* User-confirmed IC: ST7735S; panel marking: "14PIN HD14008H14 JY".
 * 128x128 SPI module; physical offsets/color order still need bench validation.
 * Keep the provisional numeric profile until module-specific data is available.
 */
#define TFT_X_OFFSET 2u
#define TFT_Y_OFFSET 3u
#define TFT_MADCTL 0xc8u
#define TFT_INVERT 0u
/* Temporary white-screen diagnostic: same panel profile, GPIO SPI mode 0.
 * Set to 0 to return to the AXI Quad SPI transport after bench validation. */
#define TFT_SOFTWARE_SPI 1u
/* 0: original provisional profile; 1: Waveshare 1.44-inch LCD HAT reference.
 * Same controller/resolution; not yet validated for the HD14008H14 JY panel. */
#define TFT_INIT_PROFILE 1u
#endif
