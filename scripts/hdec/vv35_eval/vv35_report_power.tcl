# VV35 post-route power reporting against a frozen routed checkpoint.
#
# Usage, vectorless:
#   vivado -mode batch -source vv35_report_power.tcl -tclargs \
#     <route.dcp> <out_root> <run_label> NONE NONE
#
# Usage, SAIF annotated:
#   vivado -mode batch -source vv35_report_power.tcl -tclargs \
#     <route.dcp> <out_root> <run_label> <activity.saif> <strip_path>
#
# The strip path must be the hierarchy above the hdec_top DUT in the SAIF,
# for example "tb_vv35_power_profiles/dut".  Supplying NONE selects the
# Vivado vectorless estimate and never masquerades as workload activity.

if {$argc != 5} {
    error "Expected: <route.dcp> <out_root> <run_label> <saif|NONE> <strip_path|NONE>"
}

set dcp_file   [file normalize [lindex $argv 0]]
set out_root   [file normalize [lindex $argv 1]]
set run_label  [lindex $argv 2]
set saif_arg   [lindex $argv 3]
set strip_path [lindex $argv 4]

if {![file exists $dcp_file]} {
    error "Routed checkpoint does not exist: $dcp_file"
}

file mkdir $out_root

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

open_checkpoint $dcp_file

set activity_mode "vectorless"
set saif_file "NONE"
if {$saif_arg ne "NONE"} {
    set saif_file [file normalize $saif_arg]
    if {![file exists $saif_file]} {
        error "SAIF file does not exist: $saif_file"
    }
    if {$strip_path eq "NONE" || $strip_path eq ""} {
        error "A non-empty SAIF strip_path is required"
    }
    read_saif -strip_path $strip_path $saif_file
    set activity_mode "saif"
}

set power_report [file join $out_root "${run_label}_power.rpt"]
set power_hier [file join $out_root "${run_label}_power_hier_depth3.rpt"]
report_power -file $power_report
report_power -hierarchical_depth 3 -file $power_hier

set summary ""
append summary "run_label=$run_label\n"
append summary "vivado_version=[version -short]\n"
append summary "checkpoint=$dcp_file\n"
append summary "activity_mode=$activity_mode\n"
append summary "saif_file=$saif_file\n"
append summary "strip_path=$strip_path\n"
append summary "power_report=$power_report\n"
write_text_file [file join $out_root "${run_label}_power_manifest.txt"] $summary

close_project
