# Vivado 2024.2 HDEC OOC timing atlas.
#
# Usage:
#   vivado -mode batch -source scripts/hdec/ooc_hdec_timing_atlas.tcl \
#     -tclargs <repo_root> <out_root> <period_ns> <run_label> ?<vv33_enable>?

if {($argc != 4) && ($argc != 5)} {
    error "Expected: <repo_root> <out_root> <period_ns> <run_label> ?<vv33_enable>?"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]
set run_label [lindex $argv 3]
set vv33_enable [expr {$argc == 5 ? [lindex $argv 4] : ""}]

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

proc path_cell_summary {path} {
    array set counts {}
    if {[catch {set cells [get_cells -quiet -of_objects $path]}]} {
        return ""
    }
    foreach cell $cells {
        set ref [get_property REF_NAME $cell]
        if {[regexp {^(CARRY4|LUT[1-6]|MUXF[7-9]|RAM.*|FD.*)$} $ref]} {
            if {![info exists counts($ref)]} {
                set counts($ref) 0
            }
            incr counts($ref)
        }
    }
    set result {}
    foreach ref [lsort [array names counts]] {
        lappend result "${ref}=$counts($ref)"
    }
    return [join $result ";"]
}

proc path_class_guess {startpoint endpoint cells} {
    set t [string tolower "$startpoint $endpoint $cells"]
    if {[regexp {hmatch_update|hmatch_best|hmatch_candidate|hsim_total} $t]} {
        return "HMATCH reduction/compare"
    }
    if {[regexp {popcount_q|i_p2_pop_slice|lane_popcnt} $t]} {
        return "P2 popcount capture"
    }
    if {[regexp {lane_result|lane_clip|lane_shift|lane_cnt} $t]} {
        return "P2 lane result capture"
    }
    if {[regexp {i_vrf|vrf|bank_ra|bank_we|bank_wa} $t]} {
        return "VRF/read/writeback"
    }
    if {[regexp {res_q|scalar_response|response} $t]} {
        return "scalar response"
    }
    if {[regexp {state|st_q|uop_p|fsm} $t]} {
        return "TOP control"
    }
    return "other"
}

proc export_paths_csv {outfile paths} {
    set fh [open $outfile w]
    puts $fh "rank,slack_ns,required_time_ns,data_path_delay_ns,logic_delay_ns,route_delay_ns,route_ratio,logic_levels,startpoint,endpoint,path_class,main_cells"
    set rank 0
    foreach path $paths {
        incr rank
        set startpoint [safe_get_property STARTPOINT_PIN $path]
        set endpoint [safe_get_property ENDPOINT_PIN $path]
        set slack [safe_get_property SLACK $path]
        set req [safe_get_property REQUIREMENT $path]
        set delay [safe_get_property DATAPATH_DELAY $path]
        set logic [safe_get_property DATAPATH_LOGIC_DELAY $path]
        set route [safe_get_property DATAPATH_NET_DELAY $path]
        set levels [safe_get_property LOGIC_LEVELS $path]
        set cells [path_cell_summary $path]
        set route_ratio ""
        if {$delay ne "" && $delay != 0 && $route ne ""} {
            set route_ratio [format "%.3f" [expr {$route / $delay}]]
        }
        set cls [path_class_guess $startpoint $endpoint $cells]
        puts $fh "$rank,$slack,$req,$delay,$logic,$route,$route_ratio,$levels,[csv_quote $startpoint],[csv_quote $endpoint],[csv_quote $cls],[csv_quote $cells]"
    }
    close $fh
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

create_project -in_memory "hdec_timing_atlas_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

if {$vv33_enable eq ""} {
    synth_design -top $top_module -part $part_name -mode out_of_context
} else {
    synth_design -top $top_module -part $part_name -mode out_of_context \
        -generic "VV33_FINE_INTERLEAVE=$vv33_enable"
}

report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 50 -file [file join $reports_dir "timing_summary_top50.rpt"]
report_timing -delay_type max -max_paths 1000 -sort_by slack -input_pins -nets -file [file join $reports_dir "timing_top1000.rpt"]
report_utilization -file [file join $reports_dir "utilization.rpt"]
report_utilization -hierarchical -file [file join $reports_dir "utilization_hier.rpt"]

set top_paths [get_timing_paths -delay_type max -sort_by slack -max_paths 1000 -nworst 1]
export_paths_csv [file join $reports_dir "timing_top1000.csv"] $top_paths
export_paths_csv [file join $reports_dir "timing_top200.csv"] [lrange $top_paths 0 199]

set worst_path [lindex $top_paths 0]
set wns [safe_get_property SLACK $worst_path "NA"]
set endpoint [safe_get_property ENDPOINT_PIN $worst_path "NA"]
set delay [safe_get_property DATAPATH_DELAY $worst_path "NA"]
set fmax_est "NA"
if {$wns ne "NA"} {
    set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}
write_text_file [file join $reports_dir "run_summary.txt"] "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nwns=$wns\nworst_data_delay_ns=$delay\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\nvivado_version=[version -short]\n"

close_project
