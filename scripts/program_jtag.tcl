# Run manually ONLY after verifying docs/HARDWARE.md and your actual wiring.
# This loads volatile FPGA/OCM state, not QSPI/SD persistent boot firmware.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(FPGA2026_ROOT)]} {set root $::env(FPGA2026_ROOT)}
set bit [file join $root build export system.bit]
set elf [file join $root build export analyzer.elf]
set init [file join $root build sdk hw ps7_init.tcl]
foreach f [list $bit $elf $init] {if {![file exists $f]} {error "Missing $f: build first"}}
connect
targets -set -filter {name =~ "ARM*#0"}
rst -system
after 1000
fpga -file $bit
source $init
ps7_init
ps7_post_config
targets -set -filter {name =~ "ARM*#0"}
stop
dow $elf
con
puts "JTAG image loaded. UART 115200 8N1. Volatile until power off."
