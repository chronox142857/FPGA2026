if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    open_hw
    connect_hw_server -url localhost:3121
    open_hw_target
    set_property PARAM.FREQUENCY 10000000 [current_hw_target]
    set dev [get_hw_devices -filter {PART =~ "xc7z010*"}]
    current_hw_device $dev
    set_property PROBES.FILE [file join $root build st7735s_top.ltx] $dev
    refresh_hw_device -update_hw_probes true $dev
    set ila [get_hw_ilas -of_objects $dev]
    if {[llength $ila] != 1} {error "Expected one LCD ILA"}
    reset_hw_ila $ila
    set cs [get_hw_probes -of_objects $ila -filter {NAME == "lcd_cs_n_OBUF"}]
    if {[llength $cs] != 1} {error "LCD chip-select probe not found"}
    set_property TRIGGER_COMPARE_VALUE {eq1'b0} $cs
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila $ila
    wait_on_hw_ila -timeout 10 $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -force -csv_file [file join $root build lcd_spi_trace.csv] $data
    puts "LCD_SPI_TRACE_CAPTURED"
    close_hw_target
    disconnect_hw_server
    close_hw
} msg opts]} {
    puts stderr "LCD_SPI_CAPTURE_FAILED: $msg"
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit
