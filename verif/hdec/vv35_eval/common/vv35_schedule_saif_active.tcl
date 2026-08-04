# Canonical VV35 active-window SAIF capture for either scheduling scenario.
#
# Requirements:
#   * elaborate with `xelab -debug typical` (or `-debug all`);
#   * select SERIAL/INTERLEAVED using one of the adjacent .xsim.f files;
#   * invoke XSim from the directory that receives the SAIF file.
#
# metric_active rises immediately after the background-PMUL start response and
# falls after both PMUL and the fixed HMATCH stream have completed.  Vector
# preload, final result reads and status checks therefore remain outside the
# activity window, while the exact matched-workload makespan is included.
set saif_path "vv35_schedule_active.saif"
if {[info exists ::env(VV35_SAIF_PATH)]
    && ($::env(VV35_SAIF_PATH) ne "")} {
    set saif_path $::env(VV35_SAIF_PATH)
}

set metric_path "/tb_vv35_schedule_evidence/metric_active"
set start_condition [add_condition \
    "$metric_path == 1" \
    {stop}]
run all
remove_conditions $start_condition

open_saif $saif_path
log_saif [get_objects -r /tb_vv35_schedule_evidence/h/dut/*]

set stop_condition [add_condition \
    "$metric_path == 0" \
    {stop}]
run all
close_saif
remove_conditions $stop_condition

# Complete the out-of-window correctness checks and preserve the PASS marker.
run all
quit
