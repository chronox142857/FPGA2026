# Arguments are ELF-derived addresses of screen_ok, state, last_paint, record, ui.
# No LCD reads or waveform probes: only host registers and paused CPU variables.
if {[catch {
    if {[llength $argv]!=5} {error "Expected five symbol addresses"}
    foreach address $argv {if {![regexp {^0x[0-9a-fA-F]+$} $address]} {error "Invalid symbol address"}}
    connect
    targets -set -filter {name =~ "ARM*#0"}
    if {[catch {stop} message] && ![string match "*Already stopped*" $message]} {error $message}
    after 100
    set failed [catch {
        puts "CPU_PC [rrd pc]"
        targets -set -filter {name == "APU"}
        configparams force-mem-access 1
        set capture_id [mrd -value -force 0x43c00000]
        set display_id [mrd -value -force 0x44a00000]
        set status [mrd -value -force 0x44a00004]
        set frames [mrd -value -force 0x44a0000c]
        # A just-started full frame finishes independently while ARM is paused.
        for {set attempt 0} {$frames==0 && ($status&2) && $attempt<20} {incr attempt} {
            after 100
            set status [mrd -value -force 0x44a00004]
            set frames [mrd -value -force 0x44a0000c]
        }
        set screen [mrd -value -force [lindex $argv 0]]
        puts "CAPTURE_ID=$capture_id DISPLAY_ID=$display_id DISPLAY_STATUS=$status FRAMES=$frames SCREEN_OK=$screen"
        puts "FIRMWARE_STATE [mrd -force [lindex $argv 1]]"
        puts "FIRMWARE_LAST_PAINT [mrd -force [lindex $argv 2] 2]"
        puts "FIRMWARE_RECORD [mrd -force [lindex $argv 3] 8]"
        puts "FIRMWARE_UI [mrd -force [lindex $argv 4] 4]"
        puts "DEBOUNCED_KEYS [mrd -force 0x43c00064]"
        if {$capture_id!=0x4c410101 || $display_id!=0x4c440101} {error "Interface ID mismatch"}
        if {!($status&1) || ($status&4) || $frames<1 || $screen!=1} {error "Display not ready or initial frame not completed"}
    } message]
    targets -set -filter {name =~ "ARM*#0"}
    set resume_failed [catch {con} resume_message]
    puts "CPU_RESUMED"
    if {$failed} {error $message}
    if {$resume_failed && ![string match "*Already running*" $resume_message]} {error $resume_message}
    disconnect
    puts "INTEGRATED_STATUS_VERIFIED"
} message options]} {
    puts stderr "INTEGRATED_STATUS_FAILED: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit
