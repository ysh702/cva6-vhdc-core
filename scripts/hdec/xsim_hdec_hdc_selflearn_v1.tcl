if {$argc < 2 || $argc > 3} {
    error "Expected: <repo_root> <out_root> ?<fixture_dir>?"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
if {$argc == 3} {
    set fixture_dir [file normalize [lindex $argv 2]]
} else {
    set fixture_dir [file normalize [file join $out_root "fixture"]]
}

set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set tb_file   [file join $repo_root "verif" "hdec" "tb_hdec_hdc_selflearn_v1.sv"]
set run_dir   [file join $out_root "xsim_hdc_selflearn_v1"]

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
exec xelab tb_hdec_hdc_selflearn_v1 -s tb_hdec_hdc_selflearn_v1

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

exec xsim tb_hdec_hdc_selflearn_v1 -tclbatch $sim_tcl -testplusarg "fixture_dir=$fixture_dir"
