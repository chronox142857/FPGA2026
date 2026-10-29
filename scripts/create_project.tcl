# Vivado 2018.2. No board preset or DDR training data is assumed.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(FPGA2026_ROOT)]} {set root $::env(FPGA2026_ROOT)}
set build [file join $root build hw]
create_project -force fpga2026 $build -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [glob [file join $root rtl *.v]]
add_files -fileset constrs_1 [file join $root constraints reference_pins.xdc]
create_bd_design system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_GP0 {0} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {0} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {0} CONFIG.PCW_UART1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0} CONFIG.PCW_SD0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {0} CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0} CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} CONFIG.PCW_CPU_CPU_PLL_FREQMHZ {1300.000} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.000000}] $ps
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]
create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ 50000000 [get_bd_ports sys_clk]
create_bd_port -dir I -type rst sys_rst_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports sys_rst_n]
set capture [create_bd_cell -type module -reference la_axi analyzer]
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_bus]
set_property CONFIG.NUM_MI 5 $ic
set ram [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.0 capture_memory]
set_property -dict [list CONFIG.DATA_WIDTH 32 CONFIG.SINGLE_PORT_BRAM 1 CONFIG.PROTOCOL AXI4LITE CONFIG.ECC_TYPE 0] $ram
set spi [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi:3.2 display_spi]
set_property -dict [list CONFIG.C_SPI_MODE 0 CONFIG.C_USE_STARTUP 0 CONFIG.C_NUM_SS_BITS 1 CONFIG.C_SCK_RATIO 8 CONFIG.C_FIFO_DEPTH 16] $spi
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 display_gpio]
set_property -dict [list CONFIG.C_GPIO_WIDTH 3 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT {0x00000000}] $gpio
set uart [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 debug_uart]
set_property -dict [list CONFIG.C_BAUDRATE 115200 CONFIG.C_DATA_BITS 8 CONFIG.C_USE_PARITY 0 CONFIG.C_S_AXI_ACLK_FREQ_HZ 50000000] $uart
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 resets]
set and_reset [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 reset_and]
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION and] $and_reset
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_one]
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_zero]
set_property CONFIG.CONST_VAL 0 $zero
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi_bus/ACLK] [get_bd_pins axi_bus/S00_ACLK] \
    [get_bd_pins analyzer/clk] [get_bd_pins capture_memory/s_axi_aclk] [get_bd_pins display_spi/s_axi_aclk] \
    [get_bd_pins display_spi/ext_spi_clk] [get_bd_pins display_gpio/s_axi_aclk] [get_bd_pins debug_uart/s_axi_aclk] [get_bd_pins resets/slowest_sync_clk]
connect_bd_net [get_bd_ports sys_rst_n] [get_bd_pins reset_and/Op1]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset_and/Op2]
# 2018.2 propagates the active-low sys_rst_n polarity through this AND.
connect_bd_net [get_bd_pins reset_and/Res] [get_bd_pins resets/ext_reset_in]
connect_bd_net [get_bd_pins constant_one/dout] [get_bd_pins resets/dcm_locked]
connect_bd_net [get_bd_pins constant_zero/dout] [get_bd_pins resets/aux_reset_in] [get_bd_pins resets/mb_debug_sys_rst] \
    [get_bd_pins display_spi/io0_i] [get_bd_pins display_spi/io1_i]
connect_bd_net [get_bd_pins resets/interconnect_aresetn] [get_bd_pins axi_bus/ARESETN] [get_bd_pins axi_bus/S00_ARESETN]
connect_bd_net [get_bd_pins resets/peripheral_aresetn] [get_bd_pins analyzer/rst_n] [get_bd_pins capture_memory/s_axi_aresetn] \
    [get_bd_pins display_spi/s_axi_aresetn] [get_bd_pins display_gpio/s_axi_aresetn] [get_bd_pins debug_uart/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_bus/S00_AXI]
set destinations {analyzer/s_axi capture_memory/S_AXI display_spi/AXI_LITE display_gpio/S_AXI debug_uart/S_AXI}
for {set i 0} {$i<5} {incr i} {
    set prefix [format "axi_bus/M%02d" $i]
    connect_bd_net [get_bd_ports sys_clk] [get_bd_pins ${prefix}_ACLK]
    connect_bd_net [get_bd_pins resets/interconnect_aresetn] [get_bd_pins ${prefix}_ARESETN]
    connect_bd_intf_net [get_bd_intf_pins ${prefix}_AXI] [get_bd_intf_pins [lindex $destinations $i]]
}
connect_bd_intf_net [get_bd_intf_pins capture_memory/BRAM_PORTA] [get_bd_intf_pins analyzer/capture_bram]
foreach {name dir width pin} {probe I 8 analyzer/probe keys_n I 2 analyzer/keys_n leds O 2 analyzer/leds test_io IO 4 analyzer/test_io tft_ctrl O 3 display_gpio/gpio_io_o} {
    create_bd_port -dir $dir -from [expr {$width-1}] -to 0 $name
    connect_bd_net [get_bd_ports $name] [get_bd_pins $pin]
}
foreach {name dir pin} {tft_sck O display_spi/sck_o tft_mosi O display_spi/io0_o tft_cs_n O display_spi/ss_o uart_rxd I debug_uart/rx uart_txd O debug_uart/tx} {
    create_bd_port -dir $dir $name
    connect_bd_net [get_bd_ports $name] [get_bd_pins $pin]
}
foreach {path base range} {
    analyzer/s_axi 0x43c00000 4K
    capture_memory/S_AXI 0x42000000 32K
    display_spi/AXI_LITE 0x44a00000 64K
    display_gpio/S_AXI 0x41200000 64K
    debug_uart/S_AXI 0x40600000 64K
} {
    set slave_seg [lindex [get_bd_addr_segs -of_objects [get_bd_intf_pins $path]] 0]
    create_bd_addr_seg -range $range -offset $base [get_bd_addr_spaces ps7/Data] $slave_seg SEG_[string map {/ _} $path]
}
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH $rst] != 0} {error "Unexpected reset polarity; active-low reset required"}
save_bd_design
generate_target all [get_files system.bd]
set wrapper [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT_READY=$build/fpga2026.xpr"
