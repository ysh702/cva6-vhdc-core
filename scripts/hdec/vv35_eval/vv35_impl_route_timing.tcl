# VV35 methodology-corrected OOC implementation for Vivado 2024.2.
#
# Differences from vv35_impl_route.tcl are implementation-only:
#   * models the OOC clock entry using a verified legal BUFGCTRL site;
#   * applies post-place physical optimization;
#   * uses the timing-oriented Explore route directive.
# RTL, target, 5 ns constraint and design hierarchy are unchanged.
#
# Usage:
#   vivado -mode batch -source vv35_impl_route_timing.tcl -tclargs \
#     <repo_root> <out_root> <period_ns> <run_label> <bufgctrl_site>

if {$argc != 5} {
    error "Expected: <repo_root> <out_root> <period_ns> <run_label> <bufgctrl_site>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set run_label [lindex $argv 3]
set clk_src   [lindex $argv 4]

if {![string is double -strict $period_ns] || $period_ns <= 0.0} {
    error "period_ns must be a positive number, got '$period_ns'"
}

set part_name   "xc7z020clg400-2"
set top_module  "hdec_top"
set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set reports_dir [file join $out_root "reports"]
set dcp_dir     [file join $out_root "dcp"]
set work_dir    [file join $out_root "vivado"]
foreach dir [list $out_root $reports_dir $dcp_dir $work_dir] {
    file mkdir $dir
}

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc require_file {path} {
    if {![file exists $path]} {
        error "Required source does not exist: $path"
    }
}

set rtl_files [list \
    [file join $rtl_dir "hdec_pkg.sv"] \
    [file join $rtl_dir "hdec_resource_pkg.sv"] \
    [file join $rtl_dir "hdec_vrf_64x256.sv"] \
    [file join $rtl_dir "hdec_lane_boolean_mask.sv"] \
    [file join $rtl_dir "hdec_lane_popcount_compressor.sv"] \
    [file join $rtl_dir "hdec_p2_pop_slice.sv"] \
    [file join $rtl_dir "hdec_cnt_array.sv"] \
    [file join $rtl_dir "hdec_lane_shift_align.sv"] \
    [file join $rtl_dir "hdec_lane_clip.sv"] \
    [file join $rtl_dir "hdec_lane_4x64.sv"] \
    [file join $rtl_dir "hdec_top.sv"] \
]
foreach path $rtl_files {
    require_file $path
}

set xdc_file [file join $work_dir "${run_label}_${period_ns}ns.xdc"]
set xdc_text ""
append xdc_text "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"
append xdc_text "set_property HD.CLK_SRC $clk_src \[get_ports clk_i\]\n"
write_text_file $xdc_file $xdc_text

create_project -in_memory "vv35_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context
set legal_clk_src [get_sites -quiet $clk_src]
if {[llength $legal_clk_src] != 1 || \
        [get_property SITE_TYPE $legal_clk_src] ne "BUFGCTRL"} {
    error "clk_src '$clk_src' is not one legal BUFGCTRL site on $part_name"
}
write_checkpoint -force [file join $dcp_dir "01_synth.dcp"]
report_utilization -file [file join $reports_dir "01_synth_utilization.rpt"]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir "01_synth_timing_summary.rpt"]

opt_design
write_checkpoint -force [file join $dcp_dir "02_opt.dcp"]

place_design
write_checkpoint -force [file join $dcp_dir "03_place_pre_physopt.dcp"]
phys_opt_design -directive Explore
write_checkpoint -force [file join $dcp_dir "04_place_physopt.dcp"]
report_utilization -file [file join $reports_dir "04_place_utilization.rpt"]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir "04_place_timing_summary.rpt"]

route_design -directive Explore
write_checkpoint -force [file join $dcp_dir "05_route.dcp"]

report_utilization -file [file join $reports_dir "05_route_utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "05_route_utilization_hier.rpt"]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 100 \
    -file [file join $reports_dir "05_route_timing_summary.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_top200.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_internal_reg2reg_top200.rpt"]
report_route_status -file [file join $reports_dir "05_route_status.rpt"]
report_drc -file [file join $reports_dir "05_route_drc.rpt"]
report_methodology -file [file join $reports_dir "05_route_methodology.rpt"]
report_clock_utilization \
    -file [file join $reports_dir "05_route_clock_utilization.rpt"]
report_power -file [file join $reports_dir "05_route_power_vectorless.rpt"]

set timing_paths [get_timing_paths -delay_type max -sort_by slack \
    -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    set wns "NO_PATH"
    set delay "NO_PATH"
    set endpoint "NO_PATH"
    set fmax_est "NO_PATH"
} else {
    set worst_path [lindex $timing_paths 0]
    set wns [get_property SLACK $worst_path]
    set delay [get_property DATAPATH_DELAY $worst_path]
    set endpoint [get_property ENDPOINT_PIN $worst_path]
    set fmax_est [format "%.3f" \
        [expr {1000.0 / ($period_ns - $wns)}]]
}

set internal_paths [get_timing_paths -delay_type max -sort_by slack \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1]
if {[llength $internal_paths] == 0} {
    set internal_wns "NO_PATH"
    set internal_delay "NO_PATH"
    set internal_endpoint "NO_PATH"
    set internal_fmax_est "NO_PATH"
} else {
    set internal_path [lindex $internal_paths 0]
    set internal_wns [get_property SLACK $internal_path]
    set internal_delay [get_property DATAPATH_DELAY $internal_path]
    set internal_endpoint [get_property ENDPOINT_PIN $internal_path]
    set internal_fmax_est [format "%.3f" \
        [expr {1000.0 / ($period_ns - $internal_wns)}]]
}

set summary ""
append summary "run_label=$run_label\n"
append summary "repo_root=$repo_root\n"
append summary "part=$part_name\n"
append summary "top=$top_module\n"
append summary "period_ns=$period_ns\n"
append summary "vivado_version=[version -short]\n"
append summary "clk_src=$clk_src\n"
append summary "implementation_strategy=place_default+phys_opt_Explore+route_Explore\n"
append summary "wns_ns=$wns\n"
append summary "worst_data_delay_ns=$delay\n"
append summary "fmax_est_mhz=$fmax_est\n"
append summary "top_endpoint=$endpoint\n"
append summary "internal_reg2reg_wns_ns=$internal_wns\n"
append summary "internal_reg2reg_data_delay_ns=$internal_delay\n"
append summary "internal_reg2reg_fmax_est_mhz=$internal_fmax_est\n"
append summary "internal_reg2reg_endpoint=$internal_endpoint\n"
append summary "ooc_io_caveat=Package IO paths are not placement-accurate without HD.PARTPIN_LOCS; use internal reg-to-reg timing as the core timing evidence.\n"
append summary "checkpoint=[file join $dcp_dir 05_route.dcp]\n"
write_text_file [file join $reports_dir "run_summary.txt"] $summary

close_project
