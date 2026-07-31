if {$argc != 2} {
    error "Expected: <checkpoint> <out_root>"
}

set checkpoint [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
file mkdir $out_root
open_checkpoint $checkpoint

set summary_file [file join $out_root "cpath_cells.txt"]
set fh [open $summary_file w]
foreach {label pattern} {
    leaf_product {.*ecc_leaf_prod_q_reg.*}
    sub_index    {.*ecc_kpd64_sub_q_reg.*}
    leaf_path    {.*ecc_leaf_path_q_reg.*}
    field_state  {.*hdc_src0_q_reg.*}
    direct_map   {.*ecc_direct_reduce.*}
    xor0         {.*xor0.*}
} {
    set cells [get_cells -hier -quiet -regexp $pattern]
    puts $fh "$label=[llength $cells]"
    foreach cell $cells {
        puts $fh "  $cell [get_property REF_NAME $cell]"
    }
}
close $fh

set leaf_cells [get_cells -hier -quiet -regexp {.*ecc_leaf_prod_q_reg.*}]
set state_cells [get_cells -hier -quiet -regexp {.*hdc_src0_q_reg.*}]
set leaf_q [get_pins -quiet -of_objects $leaf_cells \
    -filter {DIRECTION == OUT}]
set state_d [get_pins -quiet -of_objects $state_cells \
    -filter {DIRECTION == IN && NAME =~ */D}]
if {([llength $leaf_q] != 0) && ([llength $state_d] != 0)} {
    report_timing -from $leaf_q -to $state_d -max_paths 50 \
        -path_type full -file [file join $out_root "leaf_to_state_timing.rpt"]
}

set bitmatrix_cells [get_cells -hier -quiet -regexp {.*ecc_bitmatrix_product.*}]
set bitmatrix_q [get_pins -quiet -of_objects $bitmatrix_cells \
    -filter {DIRECTION == OUT}]
if {([llength $bitmatrix_q] != 0) && ([llength $state_d] != 0)} {
    report_timing -from $bitmatrix_q -to $state_d -max_paths 50 \
        -path_type full -file [file join $out_root "bitmatrix_to_state_timing.rpt"]
}

close_design
