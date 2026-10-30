source [file join [file dirname [info script]] create_project.tcl]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $root build timing_summary.rpt]
if {$debug_enabled} {report_bus_skew -file [file join $root build bus_skew.rpt]}
report_utilization -file [file join $root build utilization.rpt]
report_drc -file [file join $root build drc.rpt]
if {[llength [get_timing_paths -quiet -max_paths 1 -slack_lesser_than 0]]} {error "Setup timing failed"}
if {[llength [get_timing_paths -quiet -delay_type min -max_paths 1 -slack_lesser_than 0]]} {error "Hold timing failed"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]]} {error "DRC failed"}
file copy -force [file join $root build vivado st7735s_7010.runs impl_1 st7735s_top.bit] [file join $root build st7735s_top.bit]
if {$debug_enabled} {write_debug_probes -force [file join $root build st7735s_top.ltx]}
puts "BUILD_PASSED=[file join $root build st7735s_top.bit]"
