# Reference mapping from the supplied ALIENTEK 7010 FPGA examples (Vivado 2020.2).
# The 24-bit RGB LCD header is repurposed: do NOT attach a parallel RGB panel.
# Verify board revision/header numbering/3.3V before connecting or programming.
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {keys_n[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {keys_n[1]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {leds[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {leds[1]}]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_txd]
# LCD_D0..D7 -> capture CH0..CH7
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {probe[0]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {probe[1]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {probe[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {probe[3]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {probe[4]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {probe[5]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {probe[6]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {probe[7]}]
# LCD_D8..D13 -> SPI TFT (MISO unused, this is NOT I2C).
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports tft_sck]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports tft_mosi]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports tft_cs_n]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {tft_ctrl[0]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {tft_ctrl[1]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {tft_ctrl[2]}]
# LCD_D14..D17 -> optional external-loopback stimulus. Disabled after reset.
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {test_io[0]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {test_io[1]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {test_io[2]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {test_io[3]}]
# Only the first stage of each async input synchronizer is exempted.
set_false_path -from [get_ports {probe[*] keys_n[*]}] -to [get_cells -hier -filter {NAME =~ *probe_meta_reg* || NAME =~ *keys_meta_reg*}]
