if {($argc < 2) || ($argc > 4)} {
    error "Expected: <rtl_repo_root> <out_root> ?baseline_probe? ?tb_repo_root?"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set tb_root   [expr {($argc == 4)
                  ? [file normalize [lindex $argv 3]]
                  : $repo_root}]
set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set tb_file   [file join $tb_root "verif" "hdec" "vv30" "integration" \
                         "tb_vv30_hperm_contract.sv"]
set run_dir   [file join $out_root "xsim_vv30_hperm_contract"]
set baseline_probe [expr {($argc >= 3)
                       && ([lindex $argv 2] eq "baseline_probe")}]

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

puts [exec xvlog -sv {*}$rtl_files]
puts [exec xelab tb_vv30_hperm_contract -s tb_vv30_hperm_contract]

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

if {$baseline_probe} {
    puts [exec xsim tb_vv30_hperm_contract -testplusarg BASELINE_PROBE \
                                      -tclbatch $sim_tcl]
} else {
    puts [exec xsim tb_vv30_hperm_contract -tclbatch $sim_tcl]
}
