if {$argc != 2} {
    error "Expected: <repo_root> <out_root>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set tb_file   [file join $repo_root "verif" "hdec" "tb_hdec_shift_align_bit.sv"]
set run_dir   [file join $out_root "xsim_shift_align_bit"]

file mkdir $run_dir
cd $run_dir

set rtl_files [list \
    [file join $rtl_dir "hdec_lane_shift_align.sv"] \
    $tb_file \
]

exec xvlog -sv {*}$rtl_files
exec xelab tb_hdec_shift_align_bit -s tb_hdec_shift_align_bit

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

exec xsim tb_hdec_shift_align_bit -tclbatch $sim_tcl
