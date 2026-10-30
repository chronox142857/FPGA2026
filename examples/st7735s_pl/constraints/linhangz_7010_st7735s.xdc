# Previously verified Navigator ZYNQ7010 J3 wiring. Ball names are NOT
# numeric connector pin numbers. Do not connect a parallel RGB LCD here.
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]

# Screen SCL=orange, SDA=yellow, RES=green, DC=blue, CS=purple, BLK=gray.
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports lcd_sck]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW PULLUP TRUE} [get_ports lcd_mosi]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports lcd_rst_n]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports lcd_dc]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports lcd_cs_n]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports lcd_bl]

# The button is an asynchronous reset. Application deassertion is synchronized.
set_false_path -from [get_ports sys_rst_n]
# Screen input delays/board loading have not been measured; an internal timing
# pass does not establish timing or signal integrity at the external module.
