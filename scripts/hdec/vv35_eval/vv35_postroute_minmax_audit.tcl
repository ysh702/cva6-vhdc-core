# Archive setup and hold timing from the frozen routed checkpoint.
# Usage: vivado -mode batch -source vv35_postroute_minmax_audit.tcl \
#        -tclargs <route.dcp> <out_dir>

if {$argc != 2} {
    error "Expected: <route.dcp> <out_dir>"
}

set dcp_file [file normalize [lindex $argv 0]]
set out_dir  [file normalize [lindex $argv 1]]
if {![file exists $dcp_file]} {
    error "Routed checkpoint does not exist: $dcp_file"
}
file mkdir $out_dir

open_checkpoint $dcp_file
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $out_dir "timing_summary_min_max.rpt"]
report_timing -delay_type min -max_paths 20 -sort_by group \
    -file [file join $out_dir "timing_hold_paths.rpt"]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $out_dir "timing_setup_paths.rpt"]

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -quiet]
set hold_paths  [get_timing_paths -delay_type min -max_paths 1 -quiet]
set setup_slack "NA"
set hold_slack "NA"
if {[llength $setup_paths] > 0} {
    set setup_slack [get_property SLACK [lindex $setup_paths 0]]
}
if {[llength $hold_paths] > 0} {
    set hold_slack [get_property SLACK [lindex $hold_paths 0]]
}

set fh [open [file join $out_dir "timing_min_max_metrics.csv"] w]
puts $fh "metric,value_ns"
puts $fh "worst_setup_slack,$setup_slack"
puts $fh "worst_hold_slack,$hold_slack"
close $fh

puts "VV35_MINMAX_SETUP_WNS=$setup_slack"
puts "VV35_MINMAX_HOLD_WHS=$hold_slack"
close_project
