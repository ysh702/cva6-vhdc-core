# Vivado 2024.2 matched OOC synthesis for the VV30 square-reduction variants.
#
# Usage:
#   vivado -mode batch -source vv30_ooc_square_variant.tcl -tclargs \
#     <repo_root> <out_root> <period_ns> <use_xor1:0|1> <variant:1|2|3> <label>

if {$argc != 6} {
    error "Expected: <repo_root> <out_root> <period_ns> <use_xor1> <variant> <label>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set use_xor1  [lindex $argv 3]
set variant   [lindex $argv 4]
set run_label [lindex $argv 5]

if {($use_xor1 ne "0") && ($use_xor1 ne "1")} {
    error "use_xor1 must be 0 or 1"
}
if {($variant < 1) || ($variant > 3)} {
    error "variant must be 1, 2, or 3"
}

set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set reports_dir [file join $out_root "reports"]
set vivado_dir  [file join $out_root "vivado"]
set part_name   "xc7z020clg400-2"
set top_module  "hdec_top"

file mkdir $reports_dir
file mkdir $vivado_dir

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
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

set xdc_file [file join $vivado_dir "${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file \
    "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "vv30_square_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

set generics [list \
    "ECC_SQUARE_USE_XOR1=$use_xor1" \
    "ECC_SQUARE_XOR1_VARIANT=$variant" \
]
synth_design -top $top_module -part $part_name -mode out_of_context \
    -generic $generics

report_utilization \
    -file [file join $reports_dir "utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "utilization_hier.rpt"]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir "timing_summary_top50.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -input_pins -nets \
    -file [file join $reports_dir "timing_top200.rpt"]

set worst_path [lindex [
    get_timing_paths -delay_type max -sort_by slack -max_paths 1 -nworst 1
] 0]
set wns [get_property SLACK $worst_path]
set delay [get_property DATAPATH_DELAY $worst_path]
set endpoint [get_property ENDPOINT_PIN $worst_path]
set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]

write_text_file [file join $reports_dir "run_summary.txt"] \
    "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nECC_SQUARE_USE_XOR1=$use_xor1\nECC_SQUARE_XOR1_VARIANT=$variant\nwns=$wns\nworst_data_delay_ns=$delay\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\nvivado_version=[version -short]\n"

write_checkpoint -force [file join $vivado_dir "${run_label}.dcp"]
close_project
