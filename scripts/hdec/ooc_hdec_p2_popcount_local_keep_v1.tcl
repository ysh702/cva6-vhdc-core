# Vivado 2024.2 HDEC OOC script for hdec-p2-popcount-local-keep-v1.
# Keeps generated Vivado outputs under the caller-provided out_root.
#
# Usage:
#   vivado -mode batch -source scripts/hdec/ooc_hdec_p2_popcount_local_keep_v1.tcl \
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
set filelist    [file join $repo_root "core" "Flist.cva6"]
set script_path [file normalize [info script]]
set top_module  "hdec_top"
set part_name   "xc7z020clg400-2"
set full_run    [expr {$run_label eq "main"}]

if {$full_run} {
    set run_dir $reports_dir
} else {
    set run_dir [file join $reports_dir "sweep" $run_label]
}

file mkdir $reports_dir
file mkdir $vivado_dir
file mkdir $run_dir

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

proc contains_token {text pattern} {
    return [regexp -nocase $pattern $text]
}

proc path_stage_guess {text} {
    set t [string tolower $text]
    if {[regexp {hmatch|best|dist|hsim_total|lane_popcnt} $t]} {
        if {[regexp {hmatch|best|dist} $t]} {
            return "P3 HMATCH reduction/compare"
        }
        return "P2 popcount/control"
    }
    if {[regexp {hdec_p2_pop_slice|pop_q|xor_q|p1_pop|p1_xor|popcount|lane_bool|use_popcount|use_xor|uop_lane_bool_valid|lane_popcnt_n} $t]} {
        return "P2 popcount/control"
    }
    if {[regexp {gen_lane|lane_result|lane_clip|lane_shift|lane_cnt} $t]} {
        return "P2 lane-local compute"
    }
    if {[regexp {scalar_response|res_q|result_o|response} $t]} {
        return "scalar response/res_q"
    }
    if {[regexp {i_vrf|vrf|bank_ra|bank_we|bank_wa} $t]} {
        return "VRF/read/writeback"
    }
    if {[regexp {fsm|state|st_q|uop_p[0-3]|op_q} $t]} {
        return "TOP FSM/control"
    }
    return "other/unknown"
}

proc path_cell_text {path} {
    set names {}
    if {![catch {set cells [get_cells -quiet -of_objects $path]}]} {
        foreach cell $cells {
            lappend names [get_property NAME $cell]
            lappend names [get_property REF_NAME $cell]
        }
    }
    return [join $names " "]
}

proc key_tokens {text} {
    set tokens {}
    set checks {
        {HMATCH {hmatch|best|dist}}
        {HSIM {hsim}}
        {popcount {popcount}}
        {hdec_p2_pop_slice {hdec_p2_pop_slice|i_p2_pop_slice}}
        {pop_q {pop_q}}
        {xor_q {xor_q}}
        {p1_pop_d {p1_pop_d}}
        {p1_xor_d {p1_xor_d}}
        {FSM_state {FSM|fsm|state|st_q}}
        {state_q {state_q|st_q}}
        {res_q {res_q|scalar_response_q}}
        {lane_popcnt {lane_popcnt}}
        {lane_bool {lane_bool}}
        {use_popcount {use_popcount}}
        {use_xor {use_xor}}
        {uop_lane_bool_valid {uop_lane_bool_valid}}
        {lane_popcnt_n {lane_popcnt_n}}
    }
    foreach check $checks {
        set name [lindex $check 0]
        set pattern [lindex $check 1]
        if {[contains_token $text $pattern]} {
            lappend tokens $name
        }
    }
    if {[llength $tokens] == 0} {
        return "none"
    }
    return [join $tokens ";"]
}

proc path_cell_summary {path} {
    array set counts {}
    if {[catch {set cells [get_cells -quiet -of_objects $path]}]} {
        return ""
    }
    foreach cell $cells {
        set ref [get_property REF_NAME $cell]
        if {[regexp {^(CARRY4|LUT[1-6]|MUXF[7-9]|RAM.*|FD.*|BUFG.*)$} $ref]} {
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

proc export_paths_csv {outfile paths} {
    set fh [open $outfile w]
    puts $fh "rank,slack_ns,required_time_ns,arrival_time_ns,data_path_delay_ns,logic_delay_ns,route_delay_ns,logic_levels,startpoint,endpoint,startpoint_clock,endpoint_clock,path_group,major_hdec_stage_guess,key_path_tokens,main_cells"
    set rank 0
    foreach path $paths {
        incr rank
        set startpoint [safe_get_property STARTPOINT_PIN $path]
        set endpoint [safe_get_property ENDPOINT_PIN $path]
        set spclk [safe_get_property STARTPOINT_CLOCK $path]
        set epclk [safe_get_property ENDPOINT_CLOCK $path]
        set group [safe_get_property PATH_GROUP $path]
        set slack [safe_get_property SLACK $path]
        set req [safe_get_property REQUIREMENT $path]
        set arrival [safe_get_property DATAPATH_DELAY $path]
        set delay [safe_get_property DATAPATH_DELAY $path]
        set logic [safe_get_property DATAPATH_LOGIC_DELAY $path]
        set route [safe_get_property DATAPATH_NET_DELAY $path]
        set levels [safe_get_property LOGIC_LEVELS $path]
        set cell_text [path_cell_text $path]
        set text "$startpoint $endpoint $cell_text"
        set stage [path_stage_guess $text]
        set tokens [key_tokens $text]
        set cells [path_cell_summary $path]
        puts $fh "$rank,$slack,$req,$arrival,$delay,$logic,$route,$levels,[csv_quote $startpoint],[csv_quote $endpoint],[csv_quote $spclk],[csv_quote $epclk],[csv_quote $group],[csv_quote $stage],[csv_quote $tokens],[csv_quote $cells]"
    }
    close $fh
}

proc collect_pattern_objects {patterns} {
    set cells {}
    set nets {}
    foreach pat $patterns {
        set cells [concat $cells [get_cells -hier -quiet -filter "NAME =~ *$pat*"]]
        set nets  [concat $nets  [get_nets  -hier -quiet -filter "NAME =~ *$pat*"]]
    }
    return [list [lsort -unique $cells] [lsort -unique $nets]]
}

proc load_cells_for_net {net} {
    set loads [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]
    set cells {}
    foreach pin $loads {
        set cells [concat $cells [get_cells -quiet -of_objects $pin]]
    }
    return [lsort -unique $cells]
}

proc lane_set_for_cells {cells} {
    set lanes {}
    foreach cell $cells {
        set name [get_property NAME $cell]
        if {[regexp {gen_lane\[([0-9]+)\]} $name -> lane]} {
            lappend lanes $lane
        }
    }
    return [lsort -unique $lanes]
}

proc net_driver_name {net} {
    set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
    if {[llength $drivers] == 0} {
        return ""
    }
    set driver [lindex $drivers 0]
    set dcells [get_cells -quiet -of_objects $driver]
    if {[llength $dcells] == 0} {
        return [get_property NAME $driver]
    }
    return "[get_property NAME [lindex $dcells 0]]/[lindex [split [get_property NAME $driver] /] end]"
}

proc net_fanout {net} {
    return [llength [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]]
}

proc export_high_fanout_csv {outfile max_nets} {
    set candidates {}
    foreach net [get_nets -hier -quiet] {
        set fanout [net_fanout $net]
        if {$fanout > 20} {
            lappend candidates [list $fanout $net]
        }
    }
    set candidates [lsort -integer -decreasing -index 0 $candidates]
    set fh [open $outfile w]
    puts $fh "rank,net,fanout,driver,load_cells,load_lanes,cross_multiple_lanes"
    set rank 0
    foreach item [lrange $candidates 0 [expr {$max_nets - 1}]] {
        incr rank
        set fanout [lindex $item 0]
        set net [lindex $item 1]
        set loads [load_cells_for_net $net]
        set lanes [lane_set_for_cells $loads]
        set cross [expr {[llength $lanes] > 1}]
        puts $fh "$rank,[csv_quote [get_property NAME $net]],$fanout,[csv_quote [net_driver_name $net]],[llength $loads],[csv_quote [join $lanes {;}]],$cross"
    }
    close $fh
}

proc export_pattern_fanout {outfile patterns top5_csv targeted_csvs} {
    set top5_text ""
    if {[file exists $top5_csv]} {
        set fh [open $top5_csv r]
        set top5_text [read $fh]
        close $fh
    }
    set targeted_text ""
    foreach csv $targeted_csvs {
        if {[file exists $csv]} {
            set fh [open $csv r]
            append targeted_text [read $fh]
            close $fh
        }
    }

    set fh [open $outfile w]
    puts $fh "signal_or_pattern,presence,object_kind,max_fanout,objects,hierarchy,appears_in_top5,appears_in_targeted_paths,load_cells,load_lanes,cross_multiple_lanes,interpretation"
    foreach pat $patterns {
        lassign [collect_pattern_objects [list $pat]] cells nets
        set presence [expr {([llength $cells] + [llength $nets]) > 0}]
        set max_fanout 0
        set obj_names {}
        set hier {}
        set load_cells_count 0
        set load_lanes {}
        set cross 0
        foreach cell $cells {
            lappend obj_names [get_property NAME $cell]
            set h [file dirname [get_property NAME $cell]]
            lappend hier $h
        }
        foreach net $nets {
            lappend obj_names [get_property NAME $net]
            set fo [net_fanout $net]
            if {$fo > $max_fanout} {
                set max_fanout $fo
            }
            set loads [load_cells_for_net $net]
            incr load_cells_count [llength $loads]
            set lanes [lane_set_for_cells $loads]
            foreach lane $lanes {lappend load_lanes $lane}
            if {[llength $lanes] > 1} {set cross 1}
            set h [file dirname [get_property NAME $net]]
            lappend hier $h
        }
        set load_lanes [lsort -unique $load_lanes]
        set hier [lsort -unique $hier]
        set appears_top5 [expr {[string first $pat $top5_text] >= 0}]
        set appears_targeted [expr {[string first $pat $targeted_text] >= 0}]
        set interpretation "not found"
        if {$presence} {
            if {$max_fanout > 64 || $cross} {
                set interpretation "present; inspect fanout/cross-lane loads"
            } else {
                set interpretation "present; fanout appears limited"
            }
        }
        puts $fh "[csv_quote $pat],$presence,[csv_quote "cell/net"],$max_fanout,[csv_quote [join [lrange $obj_names 0 20] {;}]],[csv_quote [join [lrange $hier 0 10] {;}]],$appears_top5,$appears_targeted,$load_cells_count,[csv_quote [join $load_lanes {;}]],$cross,[csv_quote $interpretation]"
    }
    close $fh
}

proc report_targeted {name patterns out_rpt out_csv} {
    lassign [collect_pattern_objects $patterns] cells nets
    set fh [open $out_rpt w]
    puts $fh "Targeted timing group: $name"
    puts $fh "Patterns: $patterns"
    puts $fh "Matched cells ([llength $cells]):"
    foreach cell [lrange $cells 0 200] {puts $fh "  [get_property NAME $cell] [get_property REF_NAME $cell]"}
    puts $fh "Matched nets ([llength $nets]):"
    foreach net [lrange $nets 0 200] {puts $fh "  [get_property NAME $net] fanout=[net_fanout $net] driver=[net_driver_name $net]"}
    close $fh

    set through_pins {}
    if {[llength $cells] > 0} {
        set through_pins [get_pins -quiet -of_objects $cells]
    }
    if {[llength $through_pins] > 0} {
        if {[catch {
            report_timing -delay_type max -sort_by slack -max_paths 5 -nworst 1 -through $through_pins -input_pins -nets -append -file $out_rpt
            set paths [get_timing_paths -delay_type max -sort_by slack -max_paths 5 -nworst 1 -through $through_pins]
            export_paths_csv $out_csv $paths
        } msg]} {
            set fh [open $out_rpt a]
            puts $fh "\nreport_timing -through failed: $msg"
            close $fh
            set paths [get_timing_paths -delay_type max -sort_by slack -max_paths 5 -nworst 1]
            export_paths_csv $out_csv $paths
        }
    } else {
        set fh [open $out_rpt a]
        puts $fh "\nNo through pins matched; no targeted timing paths."
        close $fh
        set empty_fh [open $out_csv w]
        puts $empty_fh "rank,slack_ns,required_time_ns,arrival_time_ns,data_path_delay_ns,logic_delay_ns,route_delay_ns,logic_levels,startpoint,endpoint,startpoint_clock,endpoint_clock,path_group,major_hdec_stage_guess,key_path_tokens,main_cells"
        close $empty_fh
    }
}

proc export_local_ff_report {outfile csvfile} {
    set patterns {pop_q xor_q p1_pop_d p1_xor_d hdec_p2_pop_slice i_p2_pop_slice}
    set fh [open $outfile w]
    set csv [open $csvfile w]
    puts $csv "pattern,object_name,object_type,ref_name,hierarchy,fanout,driver,load_cells,load_lanes,cross_multiple_lanes"
    foreach pat $patterns {
        puts $fh "=== PATTERN $pat ==="
        lassign [collect_pattern_objects [list $pat]] cells nets
        puts $fh "Cells ([llength $cells]):"
        foreach cell $cells {
            set name [get_property NAME $cell]
            set ref [get_property REF_NAME $cell]
            puts $fh "  $name ref=$ref"
            puts $csv "[csv_quote $pat],[csv_quote $name],cell,[csv_quote $ref],[csv_quote [file dirname $name]],0,,0,,0"
        }
        puts $fh "Nets ([llength $nets]):"
        foreach net $nets {
            set name [get_property NAME $net]
            set fo [net_fanout $net]
            set loads [load_cells_for_net $net]
            set lanes [lane_set_for_cells $loads]
            set cross [expr {[llength $lanes] > 1}]
            set driver [net_driver_name $net]
            puts $fh "  $name fanout=$fo driver=$driver load_cells=[llength $loads] lanes=[join $lanes {,}] cross_multiple_lanes=$cross"
            puts $csv "[csv_quote $pat],[csv_quote $name],net,,[csv_quote [file dirname $name]],$fo,[csv_quote $driver],[llength $loads],[csv_quote [join $lanes {;}]],$cross"
        }
        if {[llength $cells] == 0 && [llength $nets] == 0} {
            puts $fh "  pattern not found: $pat"
        }
        puts $fh ""
    }
    close $fh
    close $csv
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

set slice_included [expr {[lsearch -glob $rtl_files "*hdec_p2_pop_slice.sv"] >= 0}]

set xdc_file [file join $vivado_dir "hdec_top_${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_p2_pop_local_keep_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -file [file join $run_dir "timing_summary.rpt"]
report_timing -delay_type max -max_paths 5 -sort_by slack -input_pins -nets -file [file join $run_dir "timing_top5.rpt"]
report_utilization -file [file join $run_dir "utilization.rpt"]
report_utilization -hierarchical -file [file join $run_dir "utilization_hier.rpt"]

set top_paths [get_timing_paths -delay_type max -sort_by slack -max_paths 5 -nworst 1]
export_paths_csv [file join $run_dir "timing_top5.csv"] $top_paths

set worst_path [lindex $top_paths 0]
set wns [safe_get_property SLACK $worst_path "NA"]
set endpoint [safe_get_property ENDPOINT_PIN $worst_path "NA"]
set stage [path_stage_guess "[safe_get_property STARTPOINT_PIN $worst_path] $endpoint [path_cell_text $worst_path]"]
set fmax_est "NA"
if {$wns ne "NA"} {
    set fmax_est [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]
}
write_text_file [file join $run_dir "run_summary.txt"] "run_label=$run_label\nperiod_ns=$period_ns\npart=$part_name\ntop=$top_module\nwns=$wns\nfmax_est_mhz=$fmax_est\ntop_endpoint=$endpoint\ntop_stage=$stage\nhdec_p2_pop_slice_included=$slice_included\n"

if {$full_run} {
    report_targeted "P2 targeted" \
        {p1_pop_d p1_xor_d pop_q xor_q hdec_p2_pop_slice i_p2_pop_slice lane_popcnt popcount lane_bool lane_valid use_popcount use_xor uop_lane_bool_valid lane_popcnt_n} \
        [file join $reports_dir "timing_p2_targeted.rpt"] \
        [file join $reports_dir "timing_p2_targeted.csv"]

    report_targeted "HMATCH targeted" \
        {hmatch match best dist acc hsim_total lane_popcnt} \
        [file join $reports_dir "timing_hmatch_targeted.rpt"] \
        [file join $reports_dir "timing_hmatch_targeted.csv"]

    report_targeted "HDEC targeted" \
        {hdec p1_pop_d p1_xor_d pop_q xor_q hmatch hsim res_q result scalar_response lane_popcnt vrf} \
        [file join $reports_dir "timing_hdec_targeted.rpt"] \
        [file join $reports_dir "timing_hdec_targeted.csv"]

    if {[catch {report_high_fanout_nets -max_nets 100 -file [file join $reports_dir "high_fanout.rpt"]} msg]} {
        if {[catch {report_design_analysis -high_fanout_nets -file [file join $reports_dir "high_fanout.rpt"]} msg2]} {
            write_text_file [file join $reports_dir "high_fanout.rpt"] "Built-in high fanout reports unavailable:\n$msg\n$msg2\nGenerated high_fanout.csv by Tcl traversal.\n"
        }
    }
    export_high_fanout_csv [file join $reports_dir "high_fanout.csv"] 100

    set hdec_patterns {p1_pop_d p1_xor_d pop_q xor_q hdec_p2_pop_slice i_p2_pop_slice lane_popcnt popcount lane_bool lane_valid state_q fsm hmatch res_q use_popcount use_xor uop_lane_bool_valid lane_popcnt_n}
    export_pattern_fanout [file join $reports_dir "high_fanout_hdec_filtered.csv"] $hdec_patterns \
        [file join $reports_dir "timing_top5.csv"] \
        [list [file join $reports_dir "timing_p2_targeted.csv"] [file join $reports_dir "timing_hmatch_targeted.csv"] [file join $reports_dir "timing_hdec_targeted.csv"]]
    set filtered_text "HDEC filtered fanout is available as high_fanout_hdec_filtered.csv\n\n"
    set filtered_fh [open [file join $reports_dir "high_fanout_hdec_filtered.csv"] r]
    append filtered_text [read $filtered_fh]
    close $filtered_fh
    write_text_file [file join $reports_dir "high_fanout_hdec_filtered.rpt"] $filtered_text

    export_local_ff_report [file join $reports_dir "local_ff_preservation.rpt"] [file join $reports_dir "local_ff_preservation.csv"]

    if {[catch {report_qor_suggestions -file [file join $reports_dir "qor_suggestions.rpt"]} msg]} {
        write_text_file [file join $reports_dir "qor_suggestions.rpt"] "report_qor_suggestions unavailable at this stage\n$msg\n"
    }

    set cfg "commit_sha=filled_by_driver\n"
    append cfg "git_describe=filled_by_driver\n"
    append cfg "branch_ref=origin/hdec-p2-popcount-microtag-p1\n"
    append cfg "vivado_version=[version -short]\n"
    append cfg "top_module=$top_module\n"
    append cfg "fpga_part=$part_name\n"
    append cfg "target_clock_period_ns=$period_ns\n"
    append cfg "ooc_tcl_script_path=$script_path\n"
    append cfg "source_filelist_path=$filelist\n"
    append cfg "hdec_p2_pop_slice_included=$slice_included\n"
    append cfg "note=No dedicated tracked HDEC OOC flow was found in target worktree; generated temporary Vivado OOC script.\n"
    write_text_file [file join $reports_dir "ooc_config.txt"] $cfg
}

close_project
