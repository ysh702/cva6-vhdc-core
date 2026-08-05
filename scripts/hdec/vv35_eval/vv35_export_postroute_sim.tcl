# Export the frozen VV35 routed checkpoint for public-interface timing simulation.
#
# Usage:
#   vivado -mode batch -source vv35_export_postroute_sim.tcl -tclargs \
#     <route.dcp> <out_dir>

if {$argc < 2 || $argc > 3} {
    error "Expected: <route.dcp> <out_dir> ?<output_stem>?"
}

set dcp_file [file normalize [lindex $argv 0]]
set out_dir  [file normalize [lindex $argv 1]]
set output_stem "hdec_top"
if {$argc == 3} { set output_stem [lindex $argv 2] }
if {![file exists $dcp_file]} {
    error "Routed checkpoint does not exist: $dcp_file"
}
file mkdir $out_dir

open_checkpoint $dcp_file
write_verilog -force -mode timesim -sdf_anno false \
    [file join $out_dir "${output_stem}_postroute_timesim.v"]
write_sdf -force -process_corner slow \
    [file join $out_dir "${output_stem}_postroute_max.sdf"]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $out_dir "postroute_export_timing.rpt"]
close_project
