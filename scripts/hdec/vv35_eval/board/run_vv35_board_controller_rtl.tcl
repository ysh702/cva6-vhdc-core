if {$argc != 2} {
    error "Expected: <repo_root> <out_root>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set rtl_dir   [file join $repo_root core hdec rtl]
set board_dir [file join $repo_root verif hdec vv35_eval board]
file mkdir $out_root

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
    [file join $board_dir vv35_board_schedule_controller.sv] \
    [file join $board_dir tb_vv35_board_schedule_controller.sv] \
]

create_project vv35_board_controller_rtl \
    [file join $out_root vivado_project] -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
add_files -norecurse $rtl_files
set_property include_dirs [list $board_dir] [get_filesets sources_1]
set_property top tb_vv35_board_schedule_controller [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
