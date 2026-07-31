if {$argc != 2} {
    error "Expected: <checkpoint> <out_root>"
}

set checkpoint [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
file mkdir $out_root
open_checkpoint $checkpoint

set summary_path [file join $out_root "leaf_d_summary.txt"]
set fh [open $summary_path w]
puts $fh "checkpoint=$checkpoint"
puts $fh "vivado_version=[version -short]"

foreach leaf_name {a b} {
    set cells [get_cells -hier -quiet -regexp \
        ".*ecc_leaf_${leaf_name}_q_reg.*"]
    set d_pins [get_pins -quiet -of_objects $cells \
        -filter {REF_PIN_NAME == D}]
    puts $fh "leaf_${leaf_name}_registers=[llength $cells]"
    puts $fh "leaf_${leaf_name}_d_pins=[llength $d_pins]"
    if {[llength $d_pins] != 0} {
        set paths [get_timing_paths -delay_type max -sort_by slack \
            -to $d_pins -max_paths 1 -nworst 1]
        if {[llength $paths] != 0} {
            set path [lindex $paths 0]
            puts $fh "leaf_${leaf_name}_worst_slack=[get_property SLACK $path]"
            puts $fh "leaf_${leaf_name}_worst_delay=[get_property DATAPATH_DELAY $path]"
            puts $fh "leaf_${leaf_name}_startpoint=[get_property STARTPOINT_PIN $path]"
            puts $fh "leaf_${leaf_name}_endpoint=[get_property ENDPOINT_PIN $path]"
            report_timing -delay_type max -sort_by slack \
                -to $d_pins -max_paths 20 -nworst 1 \
                -input_pins -nets \
                -file [file join $out_root "leaf_${leaf_name}_d_top20.rpt"]
        } else {
            puts $fh "leaf_${leaf_name}_timing_paths=0"
        }
    }
}

close $fh
close_design
