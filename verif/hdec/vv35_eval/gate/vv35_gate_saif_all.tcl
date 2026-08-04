# Short post-route mapping probe.  This is not a workload power window; it is
# used only to compare XSim debug visibility and SAIF-to-DCP net matching.
set saif_path "vv35_gate_all.saif"
if {[info exists ::env(VV35_GATE_SAIF_PATH)]
    && ($::env(VV35_GATE_SAIF_PATH) ne "")} {
    set saif_path $::env(VV35_GATE_SAIF_PATH)
}

open_saif $saif_path
log_saif [get_objects -r /tb_hdec_hdc_full_flow_v20/dut/*]
run all
close_saif
quit
