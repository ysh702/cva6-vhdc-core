# VV35 post-route gate-level active-window SAIF capture.
#
# The testbench raises metric_active only for the workload interval used in the
# serial/interleaved comparison.  Vector preload and all out-of-window result
# checks therefore remain outside the power window.  The DUT scope is the
# timesim netlist exported from the same routed checkpoint used by report_power,
# so its physical net names can be annotated directly.

set saif_path "vv35_gate_active.saif"
if {[info exists ::env(VV35_GATE_SAIF_PATH)]
    && ($::env(VV35_GATE_SAIF_PATH) ne "")} {
    set saif_path $::env(VV35_GATE_SAIF_PATH)
}

set metric_path "/tb_vv35_schedule_gate/metric_active"
set start_condition [add_condition \
    "$metric_path == 1" \
    {stop}]
run all
remove_conditions $start_condition

open_saif $saif_path
log_saif [get_objects -r /tb_vv35_schedule_gate/dut/*]

set stop_condition [add_condition \
    "$metric_path == 0" \
    {stop}]
run all
close_saif
remove_conditions $stop_condition

# Finish the public-interface result checks after the measured interval.
run all
quit
