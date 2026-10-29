set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(FPGA2026_ROOT)]} {set root $::env(FPGA2026_ROOT)}
open_project [file join $root build hw fpga2026.xpr]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $root build timing_summary.rpt]
report_utilization -file [file join $root build utilization.rpt]
report_drc -file [file join $root build drc.rpt]
set bad [get_timing_paths -quiet -max_paths 1 -slack_lesser_than 0]
if {[llength $bad]} {error "Timing failure: see timing_summary.rpt"}
set bad_hold [get_timing_paths -quiet -delay_type min -max_paths 1 -slack_lesser_than 0]
if {[llength $bad_hold]} {error "Hold timing failure: see timing_summary.rpt"}
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]
if {[llength $drc_errors]} {error "DRC errors: see drc.rpt"}
file mkdir [file join $root build export]
write_hwdef -force -file [file join $root build export system.hdf]
write_sysdef -force -hwdef [file join $root build hw fpga2026.runs impl_1 system_wrapper.hwdef] \
    -bitfile [file join $root build hw fpga2026.runs impl_1 system_wrapper.bit] \
    -file [file join $root build export system.hdf]
file copy -force [file join $root build hw fpga2026.runs impl_1 system_wrapper.bit] [file join $root build export system.bit]
puts "HARDWARE_READY (reference pinmap; board verification still required)"
