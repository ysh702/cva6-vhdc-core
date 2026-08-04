# One bounded, implementation-only timing repair probe for VV35.
#
# Starts from the methodology-corrected routed DCP, applies legal post-route
# physical optimization, then repairs routing with AggressiveExplore.  The RTL,
# clock period, clock source and functional cycle contract remain unchanged.
#
# Usage:
#   vivado -mode batch -source vv35_postroute_timing_repair.tcl -tclargs \
#     <route.dcp> <out_root> <period_ns> <run_label>

if {$argc != 4} {
    error "Expected: <route.dcp> <out_root> <period_ns> <run_label>"
}

set input_dcp  [file normalize [lindex $argv 0]]
set out_root   [file normalize [lindex $argv 1]]
set period_ns  [lindex $argv 2]
set run_label  [lindex $argv 3]
if {![file exists $input_dcp]} {
    error "Input routed checkpoint does not exist: $input_dcp"
}
if {![string is double -strict $period_ns] || $period_ns <= 0.0} {
    error "period_ns must be a positive number, got '$period_ns'"
}

set reports_dir [file join $out_root "reports"]
set dcp_dir [file join $out_root "dcp"]
file mkdir $reports_dir
file mkdir $dcp_dir

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

open_checkpoint $input_dcp

phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $dcp_dir "01_postroute_physopt.dcp"]

route_design -directive AggressiveExplore
write_checkpoint -force [file join $dcp_dir "02_postroute_repaired.dcp"]

report_utilization -file [file join $reports_dir "utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "utilization_hier.rpt"]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 100 \
    -file [file join $reports_dir "timing_summary.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $reports_dir "timing_internal_reg2reg_top200.rpt"]
report_route_status -file [file join $reports_dir "route_status.rpt"]
report_drc -file [file join $reports_dir "route_drc.rpt"]
report_methodology -file [file join $reports_dir "route_methodology.rpt"]
report_power -file [file join $reports_dir "power_vectorless.rpt"]

set paths [get_timing_paths -delay_type max -sort_by slack \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1]
if {[llength $paths] == 0} {
    set wns "NO_PATH"
    set delay "NO_PATH"
    set endpoint "NO_PATH"
    set fmax "NO_PATH"
} else {
    set path [lindex $paths 0]
    set wns [get_property SLACK $path]
    set delay [get_property DATAPATH_DELAY $path]
    set endpoint [get_property ENDPOINT_PIN $path]
    set fmax [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}

set summary ""
append summary "run_label=$run_label\n"
append summary "vivado_version=[version -short]\n"
append summary "input_checkpoint=$input_dcp\n"
append summary "period_ns=$period_ns\n"
append summary "implementation_strategy=postroute_phys_opt_AggressiveExplore+route_AggressiveExplore\n"
append summary "internal_reg2reg_wns_ns=$wns\n"
append summary "internal_reg2reg_data_delay_ns=$delay\n"
append summary "internal_reg2reg_fmax_est_mhz=$fmax\n"
append summary "internal_reg2reg_endpoint=$endpoint\n"
append summary "ooc_io_caveat=Package IO paths are not placement-accurate without HD.PARTPIN_LOCS; use internal reg-to-reg timing as the core timing evidence.\n"
append summary "checkpoint=[file join $dcp_dir 02_postroute_repaired.dcp]\n"
write_text_file [file join $reports_dir "run_summary.txt"] $summary

close_project
