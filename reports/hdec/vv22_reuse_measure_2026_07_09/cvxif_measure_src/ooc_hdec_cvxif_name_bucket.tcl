# Measurement-only OOC cell-name bucket probe for a concrete HDEC CV-X-IF top.

if {$argc != 5} {
    error "Expected: <repo_root> <out_root> <period_ns> <run_label> <measure_top_file>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set run_label [lindex $argv 3]
set measure_top_file [file normalize [lindex $argv 4]]

set reports_dir [file join $out_root "reports"]
set vivado_dir  [file join $out_root "vivado"]
set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set top_module  "hdec_cvxif_measure_top"
set part_name   "xc7z020clg400-2"

file mkdir $reports_dir
file mkdir $vivado_dir

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc bucket_for_cell {name} {
    set lname [string tolower $name]
    if {[string match "*i_vrf*" $lname]} { return "shared_vrf" }
    if {[string match "*i_vec*" $lname]} { return "shared_vec_packet_tile" }
    if {[string match "*i_accel*" $lname] && ![string match "*i_hdec_top*" $lname]} { return "cvxif_wrapper" }
    if {[regexp {ecc_pmul|ecc_job|ecc_inv|ecc_phase|ecc_subop} $lname]} { return "ecc_private_pmul_job_control" }
    if {[regexp {ecc_src|ecc_dst|ecc_acc_dst|ecc_autoreduce|ecc_raw_product|ecc_mac|ecc_sqr_repeat} $lname]} { return "ecc_private_field_control" }
    if {[regexp {ecc_diag|ecc_leaf|ecc_reduce|ecc_product|ecc_pair|bitband_pair} $lname]} { return "ecc_matrix_integration" }
    if {[regexp {hmatch|hsim|hcnt|hperm|clr|hdc_src|uop|p2_lane|p4_arch|res_q|op_q|st_q|fsm_onehot} $lname]} { return "hdc_or_shared_top_control" }
    return "other_top"
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
    [file join $rtl_dir "hdec_cvxif_wrapper.sv"] \
    $measure_top_file \
]

set xdc_file [file join $vivado_dir "hdec_cvxif_name_bucket_${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_cvxif_name_bucket_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

array set lut_counts {}
array set ff_counts {}
array set mux_counts {}
array set all_counts {}
set detail_path [file join $reports_dir "cell_name_buckets_detail.csv"]
set fh [open $detail_path w]
puts $fh "bucket,ref_name,name"
foreach cell [get_cells -hierarchical -quiet] {
    set name [get_property NAME $cell]
    set ref [get_property REF_NAME $cell]
    set bucket [bucket_for_cell $name]
    if {![info exists all_counts($bucket)]} { set all_counts($bucket) 0 }
    incr all_counts($bucket)
    if {[regexp {^LUT[1-6]$} $ref]} {
        if {![info exists lut_counts($bucket)]} { set lut_counts($bucket) 0 }
        incr lut_counts($bucket)
    } elseif {[regexp {^FD} $ref]} {
        if {![info exists ff_counts($bucket)]} { set ff_counts($bucket) 0 }
        incr ff_counts($bucket)
    } elseif {[regexp {^MUXF} $ref]} {
        if {![info exists mux_counts($bucket)]} { set mux_counts($bucket) 0 }
        incr mux_counts($bucket)
    }
    puts $fh "$bucket,$ref,$name"
}
close $fh

set summary_path [file join $reports_dir "cell_name_buckets_summary.csv"]
set buckets {}
foreach bucket [array names all_counts] { lappend buckets $bucket }
set buckets [lsort -unique $buckets]
set fh [open $summary_path w]
puts $fh "bucket,lut_cells,ff_cells,muxf_cells,total_cells"
foreach bucket $buckets {
    set l 0
    set f 0
    set m 0
    if {[info exists lut_counts($bucket)]} { set l $lut_counts($bucket) }
    if {[info exists ff_counts($bucket)]} { set f $ff_counts($bucket) }
    if {[info exists mux_counts($bucket)]} { set m $mux_counts($bucket) }
    puts $fh "$bucket,$l,$f,$m,$all_counts($bucket)"
}
close $fh

write_text_file [file join $reports_dir "probe_summary.txt"] \
    "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nvivado_version=[version -short]\n"

close_project

