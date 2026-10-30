# Volatile PL-only test. No ARM executable, PS initialization or Flash write.
if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    set bit [file join $root build st7735s_top.bit]
    if {![file exists $bit]} {error "Missing bitstream: run scripts/build.ps1 first"}
    connect -host 127.0.0.1 -port 3121
    # Prevent a previous ARM application from accessing peripherals that this
    # standalone PL image does not contain. Keep both cores suspended.
    foreach core {0 1} {
        targets -set -filter [format {name =~ "ARM*#%d"} $core]
        if {[catch {stop} stop_error] && ![string match "*Already stopped*" $stop_error]} {
            error $stop_error
        }
    }
    targets -set -filter {name == "xc7z010"}
    fpga -file $bit
    puts "LCD_FPGA_LOADED_PL_ONLY: red/green/blue fill test; volatile until power off."
    disconnect
} msg opts]} {
    puts stderr "LCD_DOWNLOAD_FAILED: $msg"
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit
