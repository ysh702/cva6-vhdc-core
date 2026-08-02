# VV33 uses the frozen VV31 RTL/common-package ordering and adds only a VV33
# testbench.  Keep the actual compile/elaborate/simulate implementation in one
# place so the two runners cannot silently diverge.
set vv33_script_dir [file dirname [file normalize [info script]]]
source [file join $vv33_script_dir ".." "vv31" "vv31_xsim_run.tcl"]
