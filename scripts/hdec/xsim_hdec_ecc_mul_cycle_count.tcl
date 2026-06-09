if {$argc != 4} {
    error "Expected: <rtl_repo_root> <tb_repo_root> <out_root> <run_label>"
}

set rtl_repo_root [file normalize [lindex $argv 0]]
set tb_repo_root  [file normalize [lindex $argv 1]]
set out_root      [file normalize [lindex $argv 2]]
set run_label     [lindex $argv 3]

set rtl_dir [file join $rtl_repo_root "core" "hdec" "rtl"]
set tb_file [file join $tb_repo_root "verif" "hdec" "tb_hdec_ecc_mul_cycle_count.sv"]
set run_dir [file join $out_root "xsim_ecc_mul_cycle_count_${run_label}"]

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

exec xvlog -sv {*}$rtl_files
exec xelab tb_hdec_ecc_mul_cycle_count -s tb_hdec_ecc_mul_cycle_count

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

exec xsim tb_hdec_ecc_mul_cycle_count -tclbatch $sim_tcl
