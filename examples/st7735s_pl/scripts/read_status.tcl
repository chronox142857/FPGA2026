# Read raw LCD responses latched by PL through a JTAG VIO core.
if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    open_hw
    connect_hw_server -url localhost:3121
    open_hw_target
    set_property PARAM.FREQUENCY 10000000 [current_hw_target]
    set dev [get_hw_devices -filter {PART =~ "xc7z010*"}]
    if {[llength $dev] != 1} {error "Expected one xc7z010"}
    current_hw_device $dev
    set_property PROBES.FILE [file join $root build st7735s_top.ltx] $dev
    refresh_hw_device -update_hw_probes true $dev
    puts "LCD_JTAG_READBACK_BEGIN"
    puts "DONE=[get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]"
    puts "EOS=[get_property {REGISTER.CONFIG_STATUS.BIT04_END_OF_STARTUP_(EOS)_STATUS} $dev]"
    set vio [get_hw_vios -of_objects $dev]
    if {[llength $vio] != 1} {error "LCD VIO core not detected; check PL clock/configuration"}
    refresh_hw_vio $vio
    foreach probe [get_hw_probes -of_objects $vio] {
        puts "VIO [get_property NAME $probe]=[get_property INPUT_VALUE $probe]"
    }
    foreach ila [get_hw_ilas -of_objects $dev] {
        puts "ILA=$ila"
        foreach probe [get_hw_probes -of_objects $ila] {puts "ILA_PROBE=[get_property NAME $probe]"}
    }
    puts "LCD_JTAG_READBACK_END"
    close_hw_target
    disconnect_hw_server
    close_hw
} msg opts]} {
    puts stderr "LCD_JTAG_READBACK_FAILED: $msg"
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit
