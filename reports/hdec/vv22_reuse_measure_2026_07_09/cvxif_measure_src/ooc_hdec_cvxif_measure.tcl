# Vivado 2024.2 measurement-only OOC for a concrete HDEC CV-X-IF top.
#
# Usage:
#   vivado -mode batch -source ooc_hdec_cvxif_measure.tcl \
#     -tclargs <repo_root> <out_root> <period_ns> <run_label> <measure_top_file>

if {$argc != 5} {
    error "Expected: <repo_root> <out_root> <period_ns> <run_label> <measure_top_file>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set run_label [lindex $argv 3]
set measure_top_file [file normalize [lindex $argv 4]]

set reports_dir [file join $out_root "reports"]
set vivado_dir  [file join $out_root "vivado"]
set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set top_module  "hdec_cvxif_measure_top"
set part_name   "xc7z020clg400-2"

file mkdir $reports_dir
file mkdir $vivado_dir

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc safe_get_property {prop obj {default ""}} {
    if {[catch {set val [get_property $prop $obj]}]} {
        return $default
    }
    return $val
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
    [file join $rtl_dir "hdec_cvxif_wrapper.sv"] \
    $measure_top_file \
]

set xdc_file [file join $vivado_dir "hdec_cvxif_measure_${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_cvxif_measure_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 50 -file [file join $reports_dir "timing_summary_top50.rpt"]
report_timing -delay_type max -max_paths 1000 -sort_by slack -input_pins -nets -file [file join $reports_dir "timing_top1000.rpt"]
report_utilization -file [file join $reports_dir "utilization.rpt"]
report_utilization -hierarchical -file [file join $reports_dir "utilization_hier.rpt"]

set top_paths [get_timing_paths -delay_type max -sort_by slack -max_paths 1000 -nworst 1]
set worst_path [lindex $top_paths 0]
set wns [safe_get_property SLACK $worst_path "NA"]
set endpoint [safe_get_property ENDPOINT_PIN $worst_path "NA"]
set delay [safe_get_property DATAPATH_DELAY $worst_path "NA"]
set fmax_est "NA"
if {$wns ne "NA"} {
    set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}
write_text_file [file join $reports_dir "run_summary.txt"] "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nwns=$wns\nworst_data_delay_ns=$delay\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\nvivado_version=[version -short]\n"

close_project

