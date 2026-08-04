# Record all switching below the committed/default hdec_top instance.
#
# This script intentionally records the complete simulation, including reset
# and untimed vector preloading.  It is a robust XSim smoke/activity export.
# A power runner that needs the canonical active-window SAIF should start and
# stop logging on tb_vv35_schedule_evidence.metric_active while retaining the
# same scope below.
# The snapshot must be elaborated with `xelab -debug typical` or `-debug all`;
# XSim rejects SAIF logging from its default no-trace snapshot.
set saif_path "vv35_schedule_activity.saif"
if {[info exists ::env(VV35_SAIF_PATH)]
    && ($::env(VV35_SAIF_PATH) ne "")} {
    set saif_path $::env(VV35_SAIF_PATH)
}
open_saif $saif_path
log_saif [get_objects -r /tb_vv35_schedule_evidence/h/dut/*]
run all
close_saif
quit
