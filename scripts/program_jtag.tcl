# Run manually ONLY after verifying docs/HARDWARE.md and your actual wiring.
# This loads volatile FPGA/OCM state, not QSPI/SD persistent boot firmware.
if {[catch {
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(FPGA2026_ROOT)]} {set root $::env(FPGA2026_ROOT)}
set bit [file join $root build export system.bit]
set elf [file join $root build export analyzer.elf]
set init [file join $root build sdk hw ps7_init.tcl]
foreach f [list $bit $elf $init] {if {![file exists $f]} {error "Missing $f: build first"}}
connect
# A PL reset during an outstanding AXI access can make the APU temporarily
# disappear from the debug target list. Configure the PL once to recover it.
if {[catch {targets -set -filter {name =~ "ARM*#0"}} target_error]} {
    puts "Recovering debug access by configuring PL first"
    targets -set -filter {name == "xc7z010"}
    fpga -file $bit
    after 500
    targets -set -filter {name =~ "ARM*#0"}
}
rst -system
after 1000
fpga -file $bit
source $init
ps7_init
ps7_post_config
targets -set -filter {name =~ "ARM*#0"}
if {[catch {stop} stop_error]} {
    if {![string match "*Already stopped*" $stop_error]} {error $stop_error}
}
# Verify PS-to-PL access before starting firmware; synthesis success cannot
# prove that the physical clock/reset chain has released the AXI peripherals.
targets -set -filter {name == "APU"}
configparams force-mem-access 1
set id_text [mrd -force 0x43c00000]
puts $id_text
if {![regexp -nocase {43c00000:\s+4c410101} $id_text]} {
    error "FPGA interface ID mismatch; CPU remains stopped"
}
set display_id [mrd -force 0x44a00000]
puts $display_id
if {![regexp -nocase {44a00000:\s+4c440101} $display_id]} {
    error "Display bridge ID mismatch; CPU remains stopped"
}
targets -set -filter {name =~ "ARM*#0"}
dow $elf
con
puts "JTAG image loaded. UART 115200 8N1. Volatile until power off."
} download_error download_options]} {
    puts stderr "JTAG_DOWNLOAD_FAILED: $download_error"
    puts stderr [dict get $download_options -errorinfo]
    exit 1
}
