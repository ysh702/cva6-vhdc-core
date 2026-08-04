# Query legal BUFGCTRL sites for the frozen Zynq-7020 target.
# Usage: vivado -mode batch -source vv35_query_clock_sites.tcl -tclargs \
#   <route_or_synth.dcp> <out_file>

if {$argc != 2} {
    error "Expected: <route_or_synth.dcp> <out_file>"
}
set dcp_file [file normalize [lindex $argv 0]]
set out_file [file normalize [lindex $argv 1]]
if {![file exists $dcp_file]} {
    error "Checkpoint does not exist: $dcp_file"
}
file mkdir [file dirname $out_file]

open_checkpoint $dcp_file
set sites [lsort [get_sites -quiet -filter {NAME =~ BUFGCTRL*}]]
if {[llength $sites] == 0} {
    error "No BUFGCTRL sites found on xc7z020clg400-2"
}
set fh [open $out_file w]
puts $fh "part=xc7z020clg400-2"
puts $fh "vivado_version=[version -short]"
puts $fh "bufgctrl_count=[llength $sites]"
foreach site $sites {
    puts $fh $site
}
close $fh
close_project
