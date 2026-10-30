# Passive FPGA output capture, READBACK_ENABLE must be zero.
if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    open_hw
    connect_hw_server -url localhost:3121
    open_hw_target
    set_property PARAM.FREQUENCY 10000000 [current_hw_target]
    set dev [get_hw_devices -filter {PART =~ "xc7z010*"}]
    if {[llength $dev]!=1} {error "Expected one FPGA"}
    current_hw_device $dev
    set_property PROBES.FILE [file join $root build st7735s_top.ltx] $dev
    refresh_hw_device -update_hw_probes true $dev
    set ila [get_hw_ilas -of_objects $dev]
    set vio [get_hw_vios -of_objects $dev]
    if {[llength $ila]!=1 || [llength $vio]!=1} {error "Expected one ILA and VIO"}
    refresh_hw_vio $vio
    foreach p [get_hw_probes -of_objects $vio] {
        if {![catch {get_property INPUT_VALUE $p} val]} {puts "STATUS [get_property NAME $p]=$val"}
    }
    set hold [get_hw_probes -of_objects $vio -filter {NAME =~ "*debug_hold_reset*"}]
    set event [get_hw_probes -of_objects $ila -filter {NAME =~ "*debug_event*"}]
    if {[llength $hold]!=1 || [llength $event]!=1} {
        foreach p [get_hw_probes -of_objects $vio] {puts "VIO_PROBE=$p"}
        foreach p [get_hw_probes -of_objects $ila] {puts "ILA_PROBE=$p"}
        error "Expected restart and event probes"
    }
    set_property OUTPUT_VALUE 1 $hold
    commit_hw_vio $hold
    reset_hw_ila $ila
    # All other compare values remain don't-care. Only output transitions store.
    set_property CAPTURE_COMPARE_VALUE {eq1'b1} $event
    set_property TRIGGER_COMPARE_VALUE {eq1'b1} $event
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CONTROL.CAPTURE_CONDITION AND $ila
    # In 2018.2 this is read-only when advanced triggering was not generated.
    if {[get_property CONTROL.TRIGGER_MODE $ila] ne "BASIC_ONLY"} {error "Unexpected ILA trigger mode"}
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila $ila
    set_property OUTPUT_VALUE 0 $hold
    commit_hw_vio $hold
    wait_on_hw_ila -timeout 15 $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -force -csv_file [file join $root build lcd_init_trace.csv] $data
    refresh_hw_vio $vio
    foreach p [get_hw_probes -of_objects $vio] {
        if {![catch {get_property INPUT_VALUE $p} val]} {puts "STATUS [get_property NAME $p]=$val"}
    }
    puts "LCD_INIT_TRACE_CAPTURED"
    close_hw_target
    disconnect_hw_server
    close_hw
} msg opts]} {
    if {[info exists hold] && [llength $hold]==1} {
        catch {set_property OUTPUT_VALUE 0 $hold;commit_hw_vio $hold}
    }
    puts stderr "LCD_INIT_CAPTURE_FAILED: $msg"
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit
