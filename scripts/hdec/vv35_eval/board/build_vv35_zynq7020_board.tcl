if {$argc != 2} {
    error "Expected: <repo_root> <out_root>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set proj_dir  [file join $out_root vivado_project]
set rpt_dir   [file join $out_root reports]
set rtl_dir   [file join $repo_root core hdec rtl]
set board_dir [file join $repo_root verif hdec vv35_eval board]
file mkdir $proj_dir
file mkdir $rpt_dir

set part_name xc7z020clg400-2
set top_name vv35_zynq7020_board_top
set vio_name vv35_zynq7020_board_vio

set rtl_files [list \
    [file join $rtl_dir hdec_pkg.sv] \
    [file join $rtl_dir hdec_resource_pkg.sv] \
    [file join $rtl_dir hdec_vrf_64x256.sv] \
    [file join $rtl_dir hdec_lane_boolean_mask.sv] \
    [file join $rtl_dir hdec_lane_popcount_compressor.sv] \
    [file join $rtl_dir hdec_p2_pop_slice.sv] \
    [file join $rtl_dir hdec_cnt_array.sv] \
    [file join $rtl_dir hdec_lane_shift_align.sv] \
    [file join $rtl_dir hdec_lane_clip.sv] \
    [file join $rtl_dir hdec_lane_4x64.sv] \
    [file join $rtl_dir hdec_top.sv] \
    [file join $board_dir vv35_zynq7020_clk200.sv] \
    [file join $board_dir vv35_board_schedule_controller.sv] \
    [file join $board_dir vv35_zynq7020_board_top.sv] \
]

foreach path [concat $rtl_files [list \
        [file join $board_dir vv35_board_preload.svh] \
        [file join $board_dir vv35_zynq7020_board.xdc]]] {
    if {![file exists $path]} {
        error "Required board source does not exist: $path"
    }
}

create_project vv35_zynq7020_board $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]

create_ip -name vio -vendor xilinx.com -library ip -module_name $vio_name
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {10} \
    CONFIG.C_NUM_PROBE_OUT {2} \
    CONFIG.C_PROBE_IN0_WIDTH {32} \
    CONFIG.C_PROBE_IN1_WIDTH {32} \
    CONFIG.C_PROBE_IN2_WIDTH {32} \
    CONFIG.C_PROBE_IN3_WIDTH {32} \
    CONFIG.C_PROBE_IN4_WIDTH {32} \
    CONFIG.C_PROBE_IN5_WIDTH {64} \
    CONFIG.C_PROBE_IN6_WIDTH {64} \
    CONFIG.C_PROBE_IN7_WIDTH {32} \
    CONFIG.C_PROBE_IN8_WIDTH {32} \
    CONFIG.C_PROBE_IN9_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {2} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x0} \
] [get_ips $vio_name]
generate_target all [get_ips $vio_name]

set vio_ip_dir [file join $proj_dir vv35_zynq7020_board.gen sources_1 ip $vio_name]
read_verilog [list \
    [file join $vio_ip_dir hdl ltlib_v1_0_vl_rfs.v] \
    [file join $vio_ip_dir hdl xsdbs_v1_0_vl_rfs.v] \
    [file join $vio_ip_dir hdl vio_v3_0_syn_rfs.v] \
    [file join $vio_ip_dir synth ${vio_name}.v] \
]
read_xdc [file join $vio_ip_dir ${vio_name}.xdc]

set_property include_dirs [list $board_dir] [current_fileset]
read_verilog -sv $rtl_files
read_xdc [file join $board_dir vv35_zynq7020_board.xdc]

synth_design -top $top_name -part $part_name
write_checkpoint -force [file join $out_root vv35_zynq7020_board_synth.dcp]
report_utilization -file [file join $rpt_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 5 \
    -file [file join $rpt_dir utilization_hierarchical_synth.rpt]
report_utilization -cells [get_cells i_controller/i_hdec_top] \
    -file [file join $rpt_dir utilization_hdec_top_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $rpt_dir timing_summary_synth.rpt]

opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

write_checkpoint -force [file join $out_root vv35_zynq7020_board_routed.dcp]
report_utilization -file [file join $rpt_dir utilization_routed.rpt]
report_utilization -hierarchical -hierarchical_depth 5 \
    -file [file join $rpt_dir utilization_hierarchical_routed.rpt]
report_utilization -cells [get_cells i_controller/i_hdec_top] \
    -file [file join $rpt_dir utilization_hdec_top_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 100 \
    -file [file join $rpt_dir timing_summary_routed.rpt]
report_bus_skew -file [file join $rpt_dir bus_skew_routed.rpt]
report_clocks -file [file join $rpt_dir clocks_routed.rpt]
report_clock_interaction -file [file join $rpt_dir clock_interaction.rpt]
report_methodology -file [file join $rpt_dir methodology_routed.rpt]
report_io -file [file join $rpt_dir io_placed.rpt]
report_route_status -file [file join $rpt_dir route_status.rpt]
report_drc -file [file join $rpt_dir drc_routed.rpt]
report_power -file [file join $rpt_dir power_vectorless_reference_only.rpt]

write_bitstream -force [file join $out_root vv35_zynq7020_board.bit]
write_debug_probes -force [file join $out_root vv35_zynq7020_board.ltx]

set fh [open [file join $rpt_dir run_summary.txt] w]
puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "input_clock=clk50_50MHz_20ns"
puts $fh "generated_clock=clk200_200MHz_5ns_from_MMCM"
puts $fh "vivado_version=[version -short]"
puts $fh "workload=one_K233_PMUL_plus_1632_four_class_HMATCH"
puts $fh "measurement_marker=NOT_BOUND_LED_CURRENT_EXCLUDED"
puts $fh "bitstream=[file join $out_root vv35_zynq7020_board.bit]"
puts $fh "debug_probes=[file join $out_root vv35_zynq7020_board.ltx]"
puts $fh "power_report=vectorless_reference_only_not_a_measured_result"
close $fh
close_project
