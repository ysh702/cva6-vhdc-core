# Vivado 2024.2 HDEC OOC FF name bucket probe.
#
# Usage:
#   vivado -mode batch -source scripts/hdec/ooc_hdec_ff_name_probe.tcl \
#     -tclargs <repo_root> <out_root> <period_ns> <run_label>

if {$argc != 4} {
    error "Expected: <repo_root> <out_root> <period_ns> <run_label>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set run_label [lindex $argv 3]

set reports_dir [file join $out_root "reports"]
set vivado_dir  [file join $out_root "vivado"]
set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set top_module  "hdec_top"
set part_name   "xc7z020clg400-2"

file mkdir $reports_dir
file mkdir $vivado_dir

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc bucket_for_cell {name} {
    set buckets {
        ecc_pmul
        ecc_product
        ecc_leaf
        ecc_diag
        ecc_reduce
        ecc_inv
        ecc_job
        uop_p
        lane_result
        hdc_src0
        hperm
        hcntclip
        hmatch
        hsim
        clr
        vrf
        st_q
        op_q
        res_q
        p2_lane_compute
        p4_arch
    }
    foreach bucket $buckets {
        if {[string match "*$bucket*" $name]} {
            return $bucket
        }
    }
    if {[string match "*FSM_onehot_st_q*" $name]} {
        return "st_q"
    }
    return "other"
}

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

set xdc_file [file join $vivado_dir "hdec_top_${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_ff_name_probe_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

set top_ffs {}
foreach cell [get_cells -hierarchical -quiet -filter {REF_NAME =~ FD*}] {
    set name [get_property NAME $cell]
    if {[string match *gen_lane* $name]} {
        continue
    }
    if {[string match *i_vrf* $name]} {
        continue
    }
    lappend top_ffs $cell
}

array set counts {}
array set refs {}
set detail_path [file join $reports_dir "top_ff_cells_by_name.csv"]
set fh [open $detail_path w]
puts $fh "bucket,ref_name,name"
foreach cell [lsort $top_ffs] {
    set name [get_property NAME $cell]
    set ref [get_property REF_NAME $cell]
    set bucket [bucket_for_cell $name]
    if {![info exists counts($bucket)]} {
        set counts($bucket) 0
    }
    incr counts($bucket)
    if {![info exists refs($bucket,$ref)]} {
        set refs($bucket,$ref) 0
    }
    incr refs($bucket,$ref)
    puts $fh "$bucket,$ref,$name"
}
close $fh

set summary_path [file join $reports_dir "top_ff_buckets.csv"]
set sorted {}
foreach bucket [array names counts] {
    lappend sorted [list $counts($bucket) $bucket]
}
set sorted [lsort -decreasing -integer -index 0 $sorted]
set fh [open $summary_path w]
puts $fh "bucket,count"
foreach pair $sorted {
    puts $fh "[lindex $pair 1],[lindex $pair 0]"
}
close $fh

set ref_path [file join $reports_dir "top_ff_bucket_refs.csv"]
set fh [open $ref_path w]
puts $fh "bucket,ref_name,count"
foreach key [lsort [array names refs]] {
    set parts [split $key ","]
    puts $fh "[lindex $parts 0],[lindex $parts 1],$refs($key)"
}
close $fh

write_text_file [file join $reports_dir "probe_summary.txt"] \
    "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nvivado_version=[version -short]\ntop_ffs=[llength $top_ffs]\n"

close_project
