# Place and route the frozen independent HDC+ECC accelerator netlist.

if {$argc != 3} {
    error "Expected: <synth.dcp> <out_root> <period_ns>"
}

set synth_dcp [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
if {![file exists $synth_dcp]} {
    error "Synthesis checkpoint does not exist: $synth_dcp"
}

set reports_dir [file join $out_root reports]
set dcp_dir [file join $out_root dcp]
file mkdir $reports_dir
file mkdir $dcp_dir

proc write_text {path value} {
    set fh [open $path w]
    puts -nonewline $fh $value
    close $fh
}

open_checkpoint $synth_dcp
set hdc_cell [get_cells -quiet u_hdc]
set ecc_cell [get_cells -quiet u_ecc]
if {[llength $hdc_cell] != 1 || [llength $ecc_cell] != 1} {
    error "Independent HDC and ECC IP instances were not preserved"
}
set_property DONT_TOUCH true [get_cells u_hdc]
set_property DONT_TOUCH true [get_cells u_ecc]

set blackboxes [get_cells -hierarchical -quiet -filter {IS_BLACKBOX}]
if {[llength $blackboxes] != 0} {
    error "Design contains [llength $blackboxes] unresolved black boxes"
}

report_utilization -file [file join $reports_dir 01_synth_utilization.rpt]
report_utilization -hierarchical \
    -file [file join $reports_dir 01_synth_utilization_hier.rpt]

opt_design
write_checkpoint -force [file join $dcp_dir 02_opt.dcp]

place_design -directive Explore
write_checkpoint -force [file join $dcp_dir 03_place.dcp]
phys_opt_design -directive Explore
write_checkpoint -force [file join $dcp_dir 03_place_physopt.dcp]
report_utilization -file [file join $reports_dir 03_place_utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir 03_place_timing_summary.rpt]

route_design -directive AggressiveExplore
write_checkpoint -force [file join $dcp_dir 04_route.dcp]
report_utilization -file [file join $reports_dir 04_route_utilization.rpt]
report_utilization -hierarchical \
    -file [file join $reports_dir 04_route_utilization_hier.rpt]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 100 \
    -file [file join $reports_dir 04_route_timing_summary.rpt]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $reports_dir 04_route_timing_reg2reg_top200.rpt]
report_route_status -file [file join $reports_dir 04_route_status.rpt]
report_drc -file [file join $reports_dir 04_route_drc.rpt]
report_power -file [file join $reports_dir 04_route_power_vectorless.rpt]

set worst_paths [get_timing_paths -delay_type max -sort_by slack \
    -max_paths 1 -nworst 1]
if {[llength $worst_paths] == 0} {
    set wns "NO_PATH"
    set fmax_est "NO_PATH"
} else {
    set wns [get_property SLACK [lindex $worst_paths 0]]
    set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}

set summary ""
append summary "vivado_version=[version -short]\n"
append summary "top=vv35_dual_accel_core_top\n"
append summary "part=xc7z020clg400-2\n"
append summary "period_ns=$period_ns\n"
append summary "implementation_strategy=place_Explore+physopt_Explore+route_AggressiveExplore\n"
append summary "route_status=[get_property ROUTE_STATUS [current_design]]\n"
append summary "wns_ns=$wns\n"
append summary "fmax_est_mhz=$fmax_est\n"
append summary "cross_ip_optimization=disabled\n"
append summary "integrated_blackbox_count=[llength $blackboxes]\n"
append summary "checkpoint=[file join $dcp_dir 04_route.dcp]\n"
write_text [file join $reports_dir run_summary.txt] $summary
close_project

puts "VV35_DUAL_INDEPENDENT_IMPL_PASS output=$out_root"
