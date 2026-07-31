# Vivado 2024.2 matched OOC synthesis for the VV30 Section IV-C method chain.
#
# Usage:
#   vivado -mode batch -source vv30_ooc_method_ablation.tcl -tclargs \
#     <repo> <out> <period_ns> <seed> <factor> <inv_redirect> \
#     <dbl_frobenius> <add_z_forward> <label>

if {$argc != 9} {
    error "Expected: <repo> <out> <period> <seed> <factor> <inv> <dbl> <add> <label>"
}

set repo_root      [file normalize [lindex $argv 0]]
set out_root       [file normalize [lindex $argv 1]]
set period_ns      [lindex $argv 2]
set residue_seed   [lindex $argv 3]
set affine_factor  [lindex $argv 4]
set inv_redirect   [lindex $argv 5]
set dbl_frobenius  [lindex $argv 6]
set add_z_forward  [lindex $argv 7]
set run_label      [lindex $argv 8]

foreach value [list $residue_seed $affine_factor $inv_redirect \
                    $dbl_frobenius $add_z_forward] {
    if {($value ne "0") && ($value ne "1")} {
        error "method-ablation controls must be 0 or 1"
    }
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

create_project -in_memory "vv30_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

set method_generics [list \
    "ECC_PMUL_RESIDUE_SEEDING=$residue_seed" \
    "ECC_PMUL_AFFINE_FACTORING=$affine_factor" \
    "ECC_INV_SQUARE_REDIRECT=$inv_redirect" \
    "ECC_PMUL_DBL_FROBENIUS=$dbl_frobenius" \
    "ECC_PMUL_ADD_Z_FORWARD=$add_z_forward" \
]
synth_design -top $top_module -part $part_name -mode out_of_context \
    -generic $method_generics

report_utilization -file [file join $reports_dir "utilization.rpt"]
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
    "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nECC_PMUL_RESIDUE_SEEDING=$residue_seed\nECC_PMUL_AFFINE_FACTORING=$affine_factor\nECC_INV_SQUARE_REDIRECT=$inv_redirect\nECC_PMUL_DBL_FROBENIUS=$dbl_frobenius\nECC_PMUL_ADD_Z_FORWARD=$add_z_forward\nwns=$wns\nworst_data_delay_ns=$delay\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\nvivado_version=[version -short]\n"

write_checkpoint -force [file join $vivado_dir "${run_label}.dcp"]
close_project
