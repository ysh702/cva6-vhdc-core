# Vivado 2024.2 HDEC V47 ECC area bucket export.
#
# Usage:
#   vivado -mode batch -source reports/hdec/v47_ecc_area_share_2026_06_17/ecc_area_bucket_v47.tcl \
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

proc csv_quote {value} {
    set value [string map {"\"" "\"\""} $value]
    return "\"$value\""
}

proc safe_get_property {prop obj {default ""}} {
    if {[catch {set val [get_property $prop $obj]}]} {
        return $default
    }
    return $val
}

proc bucket_for_cell {cell_name ref_name} {
    set n [string tolower "$cell_name $ref_name"]

    # Shared physical resources. These should not be charged to ECC alone.
    if {[regexp {(^|/)gen_lane\[[0-9]+\]\.i_lane|/i_lane/|hdec_lane_4x64} $n]} {
        return "shared_lane_operator"
    }
    if {[regexp {(^|/)i_vrf(/|$)|(^|/)i_vrf/|i_vrf/.+vrf_mem|i_vrf/.+bank_ra|i_vrf/.+bank_we|i_vrf/.+bank_wa|i_vrf/.+bank_wdata|i_vrf/.+bank_ra_data} $n]} {
        return "shared_vrf_bram"
    }
    if {[regexp {i_p2_pop_slice|popcount|popcnt|pop_} $n]} {
        return "shared_popcount_operator"
    }
    if {[regexp {i_shift_align|shift_align|lane_shift|hperm_spread|hspread} $n]} {
        return "shared_shift_spread_operator"
    }
    if {[regexp {vrf_req|vrf_ra|vrf_wa|vrf_wd|vrf_we|vrf_rd|vaddr|vwr} $n]} {
        return "shared_vrf_top_control"
    }

    # Strict ECC-exclusive buckets. These are a lower bound because synthesis can
    # absorb some ECC state decode into generic top-level state-machine logic.
    if {[regexp {ecc_product|product_pair} $n]} {
        return "ecc_exclusive_product_scratch"
    }
    if {[regexp {ecc_leaf|ecc_diag|ecc_reduce|ecc_fold|ecc_pipe|ecc_partial|ecc_acc|ecc_src|ecc_dst|ecc_autoreduce|ecc_mac|lane_ecc|kpd} $n]} {
        return "ecc_exclusive_mul_reduce_datapath"
    }
    if {[regexp {ecc_inv|ecc_pmul|ecc_job|ecc_sqr|ecc_load_bg|ecc_diag_bg} $n]} {
        return "ecc_exclusive_inv_pmul_schedule"
    }
    if {[regexp {(^|/)ecc_|ecc_} $n]} {
        return "ecc_exclusive_other_named"
    }

    # HDC-facing named control/datapath. These are not ECC-exclusive.
    if {[regexp {hmatch|hsim|hbind|hcnt|hclip|clip|cnt_|cntq|uop_|p0_|p1_|p2_|p3_|p4_|diff|mask|res_q|state_o|busy_o|ready_o|valid_i} $n]} {
        return "hdc_or_host_control"
    }

    return "unattributed_top_control"
}

proc inc2 {arr_name bucket key {amount 1}} {
    upvar $arr_name arr
    set idx "$bucket,$key"
    if {![info exists arr($idx)]} {
        set arr($idx) 0
    }
    incr arr($idx) $amount
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

create_project -in_memory "hdec_v47_ecc_area_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

report_utilization -file [file join $reports_dir "utilization.rpt"]
report_utilization -hierarchical -file [file join $reports_dir "utilization_hier.rpt"]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 20 -file [file join $reports_dir "timing_summary_top20.rpt"]

array set counts {}
array set samples {}

set leaf_fh [open [file join $reports_dir "leaf_cells.csv"] w]
puts $leaf_fh "bucket,ref_name,cell_name"

foreach cell [get_cells -hierarchical] {
    set ref [safe_get_property REF_NAME $cell]
    if {![regexp {^(LUT[1-6]|RAM.*|FD.*|LD.*|CARRY4|MUXF[7-9])$} $ref]} {
        continue
    }
    set name [safe_get_property NAME $cell]
    set bucket [bucket_for_cell $name $ref]

    if {[regexp {^LUT[1-6]$} $ref]} {
        inc2 counts $bucket LUT_CELL
        inc2 counts $bucket $ref
    } elseif {[regexp {^FD|^LD} $ref]} {
        inc2 counts $bucket FF_CELL
        inc2 counts $bucket $ref
    } elseif {[regexp {^RAMB} $ref]} {
        inc2 counts $bucket BRAM_CELL
        inc2 counts $bucket $ref
    } elseif {[regexp {^RAM} $ref]} {
        inc2 counts $bucket LUTRAM_CELL
        inc2 counts $bucket $ref
    } elseif {$ref eq "CARRY4"} {
        inc2 counts $bucket CARRY4_CELL
    } else {
        inc2 counts $bucket OTHER_CELL
        inc2 counts $bucket $ref
    }

    set sample_key "$bucket,SAMPLE_COUNT"
    if {![info exists counts($sample_key)] || $counts($sample_key) < 12} {
        inc2 counts $bucket SAMPLE_COUNT
        set sample_idx "$bucket,$counts($sample_key)"
        set samples($sample_idx) "$ref,$name"
    }

    puts $leaf_fh "[csv_quote $bucket],[csv_quote $ref],[csv_quote $name]"
}
close $leaf_fh

set buckets {}
foreach idx [array names counts] {
    set parts [split $idx ","]
    set bucket [lindex $parts 0]
    if {[lsearch -exact $buckets $bucket] < 0} {
        lappend buckets $bucket
    }
}

set summary_fh [open [file join $reports_dir "bucket_summary.csv"] w]
puts $summary_fh "bucket,lut_cells,ff_cells,lutram_cells,bram_cells,carry4_cells,other_cells,lut1,lut2,lut3,lut4,lut5,lut6"
foreach bucket [lsort $buckets] {
    set row [list $bucket]
    foreach key {LUT_CELL FF_CELL LUTRAM_CELL BRAM_CELL CARRY4_CELL OTHER_CELL LUT1 LUT2 LUT3 LUT4 LUT5 LUT6} {
        set idx "$bucket,$key"
        if {[info exists counts($idx)]} {
            lappend row $counts($idx)
        } else {
            lappend row 0
        }
    }
    puts $summary_fh [join $row ","]
}
close $summary_fh

set samples_fh [open [file join $reports_dir "bucket_samples.txt"] w]
foreach bucket [lsort $buckets] {
    puts $samples_fh "\[$bucket\]"
    for {set i 1} {$i <= 12} {incr i} {
        set key "$bucket,$i"
        if {[info exists samples($key)]} {
            puts $samples_fh $samples($key)
        }
    }
    puts $samples_fh ""
}
close $samples_fh

set top_paths [get_timing_paths -delay_type max -sort_by slack -max_paths 1 -nworst 1]
set worst_path [lindex $top_paths 0]
set wns [safe_get_property SLACK $worst_path "NA"]
set endpoint [safe_get_property ENDPOINT_PIN $worst_path "NA"]
set delay [safe_get_property DATAPATH_DELAY $worst_path "NA"]
set fmax_est "NA"
if {$wns ne "NA"} {
    set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}
write_text_file [file join $reports_dir "run_summary.txt"] "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nwns=$wns\nworst_data_delay_ns=$delay\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\nvivado_version=[version -short]\nclassification=strict_name_based_lower_bound\n"

close_project
