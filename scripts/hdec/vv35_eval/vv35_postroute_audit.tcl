# Generate timing and methodology evidence from an existing routed VV35 DCP.
# This intentionally does not assign package pins for the standalone OOC core.
# Consequently, internal sequential-to-sequential paths are the primary timing
# evidence; top-level input/output paths retain the HD.PARTPIN_LOCS caveat.
#
# Usage:
#   vivado -mode batch -source vv35_postroute_audit.tcl -tclargs \
#     <route.dcp> <out_root> <period_ns>

if {$argc != 3} {
    error "Expected: <route.dcp> <out_root> <period_ns>"
}

set dcp_file   [file normalize [lindex $argv 0]]
set out_root   [file normalize [lindex $argv 1]]
set period_ns  [lindex $argv 2]

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

report_route_status -file [file join $out_root "route_status.rpt"]
report_drc -file [file join $out_root "route_drc.rpt"]
report_methodology -file [file join $out_root "route_methodology.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $out_root "timing_internal_reg2reg_top200.rpt"]

set paths [get_timing_paths -delay_type max -sort_by slack \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1]
if {[llength $paths] == 0} {
    set wns "NO_PATH"
    set delay "NO_PATH"
    set endpoint "NO_PATH"
    set fmax "NO_PATH"
} else {
    set path [lindex $paths 0]
    set wns [get_property SLACK $path]
    set delay [get_property DATAPATH_DELAY $path]
    set endpoint [get_property ENDPOINT_PIN $path]
    set fmax [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}

set summary ""
append summary "checkpoint=$dcp_file\n"
append summary "vivado_version=[version -short]\n"
append summary "internal_reg2reg_wns_ns=$wns\n"
append summary "internal_reg2reg_data_delay_ns=$delay\n"
append summary "internal_reg2reg_fmax_est_mhz=$fmax\n"
append summary "internal_reg2reg_endpoint=$endpoint\n"
append summary "ooc_io_caveat=Package IO paths are not placement-accurate without HD.PARTPIN_LOCS; use internal reg-to-reg timing as the core timing evidence.\n"
write_text_file [file join $out_root "postroute_audit_summary.txt"] $summary

close_project
