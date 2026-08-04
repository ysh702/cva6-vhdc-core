if {$argc != 2} {
    error "Expected: <repo_root> <out_root>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set tb_file   [file join $repo_root "verif" "hdec" \
                            "tb_hdec_hdc_full_flow_v20.sv"]
set run_dir   [file join $out_root "xsim_hdc_full_flow_v20_relaxed"]

file mkdir $run_dir
cd $run_dir

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
    $tb_file \
]

puts [exec xvlog.bat -sv {*}$rtl_files]
# The legacy testbench declares a timescale while synthesizable modules rely
# on the simulator default.  Vivado 2024.2 treats that legal legacy mixture as
# a strict-language error unless --relax is set.  No design semantics change.
puts [exec xelab.bat --relax tb_hdec_hdc_full_flow_v20 \
                         -s tb_hdec_hdc_full_flow_v20]

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

puts [exec xsim.bat tb_hdec_hdc_full_flow_v20 -tclbatch $sim_tcl]
