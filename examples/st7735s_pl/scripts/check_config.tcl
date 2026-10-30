if {[catch {
    open_hw
    connect_hw_server -url localhost:3121
    open_hw_target
    set dev [get_hw_devices -filter {PART =~ "xc7z010*"}]
    if {[llength $dev] != 1} {error "Expected exactly one xc7z010"}
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    # Use the named fields exposed by this Vivado version, rather than
    # interpreting a successful upload/progress display as a running image.
    set done [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]
    set eos [get_property {REGISTER.CONFIG_STATUS.BIT04_END_OF_STARTUP_(EOS)_STATUS} $dev]
    puts "LCD_FPGA_STATUS DONE=$done EOS=$eos"
    if {$done ne "1" || $eos ne "1"} {error "FPGA configuration/startup not complete"}
    puts "LCD_FPGA_CONFIG_VERIFIED"
    close_hw_target
    disconnect_hw_server
    close_hw
} msg opts]} {
    puts stderr "LCD_CONFIG_CHECK_FAILED: $msg"
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit
