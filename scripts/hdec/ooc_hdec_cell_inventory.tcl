if {$argc != 3} {
    error "Expected: <repo_root> <out_root> <run_label>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set run_label [lindex $argv 2]
set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set part_name "xc7z020clg400-2"

file mkdir $out_root

set rtl_files [list \
    [file join $rtl_dir "hdec_pkg.sv"] \
    [file join $rtl_dir "hdec_resource_pkg.sv"] \
    [file join $rtl_dir "hdec_vrf_64x256.sv"] \
    [file join $rtl_dir "hdec_lane_boolean_mask.sv"] \
    [file join $rtl_dir "hdec_lane_popcount_compressor.sv"] \
    [file join $rtl_dir "hdec_p2_pop_slice.sv"] \
    [file join $rtl_dir "hdec_cnt_array.sv"] \
    [file join $rtl_dir "hdec_lane_shift_align.sv"] \
    [file join $rtl_dir "hdec_lane_clip.sv"] \
    [file join $rtl_dir "hdec_lane_4x64.sv"] \
    [file join $rtl_dir "hdec_top.sv"] \
]

create_project -in_memory "hdec_cell_inventory_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
synth_design -top hdec_top -part $part_name -mode out_of_context

set lut_fh [open [file join $out_root "lut_cells.csv"] w]
puts $lut_fh "ref_name,name"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]] {
    puts $lut_fh "[get_property REF_NAME $cell],$cell"
}
close $lut_fh

set prim_fh [open [file join $out_root "primitive_cells.csv"] w]
puts $prim_fh "ref_name,name"
foreach cell [lsort [get_cells -hierarchical -filter {IS_PRIMITIVE == 1}]] {
    puts $prim_fh "[get_property REF_NAME $cell],$cell"
}
close $prim_fh

set hier_fh [open [file join $out_root "hierarchy_cells.csv"] w]
puts $hier_fh "ref_name,orig_ref_name,name"
foreach cell [lsort [get_cells -hierarchical -filter {IS_PRIMITIVE == 0}]] {
    set orig_ref ""
    catch {set orig_ref [get_property ORIG_REF_NAME $cell]}
    puts $hier_fh "[get_property REF_NAME $cell],$orig_ref,$cell"
}
close $hier_fh

report_utilization -hierarchical -file [file join $out_root "utilization_hier.rpt"]
write_checkpoint -force [file join $out_root "synth.dcp"]
close_project
