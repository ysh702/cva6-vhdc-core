# Vivado 2024.2 HDEC OOC timing profile and path atlas.
#
# Usage:
#   vivado -mode batch -source scripts/vivado/ooc_hdec_timing_atlas.tcl \
#     -tclargs <repo_root> <output_root> <frequency_mhz> <period_ns> \
#       <commit_label>

if {$argc != 5} {
    error "Expected: <repo_root> <output_root> <frequency_mhz> <period_ns> <commit_label>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set freq_mhz  [lindex $argv 2]
set period_ns [lindex $argv 3]
set commit_label [lindex $argv 4]
set rtl_dir   [file join $repo_root "core" "hdec" "rtl"]
set part_name "xc7z020clg400-2"
set run_dir   [file join $out_root "${freq_mhz}mhz"]

file mkdir $run_dir
file mkdir [file join $run_dir "groups"]
file mkdir [file join $run_dir "fixed_paths"]

set rtl_files [list \
    [file join $rtl_dir "hdec_pkg.sv"] \
    [file join $rtl_dir "hdec_resource_pkg.sv"] \
    [file join $rtl_dir "hdec_vrf_64x256.sv"] \
    [file join $rtl_dir "hdec_lane_boolean_mask.sv"] \
    [file join $rtl_dir "hdec_lane_popcount_compressor.sv"] \
    [file join $rtl_dir "hdec_cnt_array.sv"] \
    [file join $rtl_dir "hdec_lane_shift_align.sv"] \
    [file join $rtl_dir "hdec_lane_clip.sv"] \
    [file join $rtl_dir "hdec_lane_4x64.sv"] \
    [file join $rtl_dir "hdec_top.sv"] \
]

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc csv_quote {value} {
    regsub -all {"} $value {""} value
    return "\"$value\""
}

proc cells_for_patterns {patterns} {
    set result {}
    foreach pattern $patterns {
        set result [concat $result \
            [get_cells -hier -quiet -filter "NAME =~ $pattern"]]
    }
    return [lsort -unique $result]
}

proc output_pins_for_cells {cells} {
    if {[llength $cells] == 0} {
        return {}
    }
    return [get_pins -quiet -of_objects $cells -filter {DIRECTION == OUT}]
}

proc input_pins_for_cells {cells pin_kinds} {
    if {[llength $cells] == 0} {
        return {}
    }

    set result {}
    foreach pin [get_pins -quiet -of_objects $cells -filter {DIRECTION == IN}] {
        set name [get_property NAME $pin]
        set leaf [lindex [split $name "/"] end]
        foreach kind $pin_kinds {
            if {$kind eq "ALL" || $leaf eq $kind ||
                ($kind eq "DATA" && [regexp {^(D|DI|S|WE|WEM|A|ADDR)} $leaf]) ||
                ($kind eq "RESET" && [regexp {^(CLR|PRE|R|S)} $leaf])} {
                lappend result $pin
                break
            }
        }
    }
    return [lsort -unique $result]
}

proc report_path_group {manifest_fh name from_patterns to_patterns pin_kinds max_paths out_dir} {
    set from_cells [cells_for_patterns $from_patterns]
    set to_cells [cells_for_patterns $to_patterns]
    set from_pins [output_pins_for_cells $from_cells]
    set to_pins [input_pins_for_cells $to_cells $pin_kinds]
    set outfile [file join $out_dir "${name}.rpt"]

    puts $manifest_fh "[csv_quote $name],[llength $from_cells],[llength $from_pins],[llength $to_cells],[llength $to_pins],[csv_quote $outfile]"

    if {[llength $to_pins] == 0} {
        write_text_file $outfile \
            "No endpoint pins matched.\nfrom_patterns=$from_patterns\nto_patterns=$to_patterns\npin_kinds=$pin_kinds\n"
        return
    }

    set args [list -delay_type max -sort_by slack -max_paths $max_paths \
        -nworst 1]
    if {[llength $from_pins] > 0} {
        lappend args -from $from_pins
    }
    lappend args -to $to_pins -file $outfile

    if {[catch {report_timing {*}$args} msg]} {
        write_text_file $outfile "report_timing failed:\n$msg\n"
    }
}

proc path_class {startpoint endpoint} {
    set text [string tolower "$startpoint $endpoint"]
    set end [string tolower $endpoint]

    if {[regexp {lane_(result|popcnt|clip)_q} $end]} {
        return "P2 lane capture"
    }
    if {[regexp {hsim_total_q} $end]} {
        return "P3 HSIM accumulate"
    }
    if {[regexp {hmatch_best_(dist|idx)_q} $end]} {
        return "P3 HMATCH best compare/update"
    }
    if {[regexp {bank_ra_data_o} $end]} {
        return "P1 VRF read/capture"
    }
    if {[regexp {i_vrf|vrf_} $end]} {
        return "VRF writeback"
    }
    if {[regexp {scalar_response_q|res_q} $end]} {
        if {[regexp {a_q|op_q|vaddr|bk_q|vrf} $text]} {
            return "fast path"
        }
        return "scalar response"
    }
    if {[regexp {/ce$} $end]} {
        return "control CE"
    }
    return "other"
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

proc export_top_paths_csv {outfile max_paths} {
    set fh [open $outfile w]
    puts $fh "rank,path_class,startpoint,endpoint,slack_ns,data_delay_ns,logic_delay_ns,route_delay_ns,route_ratio_pct,logic_levels,main_cells,notes"

    set paths [get_timing_paths -delay_type max -sort_by slack \
        -max_paths $max_paths -nworst 1]
    set rank 0
    foreach path $paths {
        incr rank
        set startpoint [get_property STARTPOINT_PIN $path]
        set endpoint [get_property ENDPOINT_PIN $path]
        set slack [get_property SLACK $path]
        set delay [get_property DATAPATH_DELAY $path]
        set logic [get_property DATAPATH_LOGIC_DELAY $path]
        set route [get_property DATAPATH_NET_DELAY $path]
        set levels [get_property LOGIC_LEVELS $path]
        set ratio 0.0
        if {$delay > 0.0} {
            set ratio [expr {100.0 * $route / $delay}]
        }
        set class [path_class $startpoint $endpoint]
        set cells [path_cell_summary $path]
        set notes ""
        if {[string match "*/CE" $endpoint]} {
            set notes "CE endpoint"
        } elseif {[string match "*/D" $endpoint]} {
            set notes "D endpoint"
        }

        puts $fh "$rank,[csv_quote $class],[csv_quote $startpoint],[csv_quote $endpoint],$slack,$delay,$logic,$route,[format %.2f $ratio],$levels,[csv_quote $cells],[csv_quote $notes]"
    }
    close $fh
}

proc export_high_fanout_csv {outfile max_nets} {
    set candidates {}
    array set unique_nets {}

    if {[catch {
        set nets [get_nets -hier -quiet -filter {FLAT_PIN_COUNT > 20}]
    }]} {
        set nets [get_nets -hier -quiet]
    }
    if {[llength $nets] == 0} {
        set nets [get_nets -hier -quiet]
    }

    foreach net $nets {
        set loads [get_pins -quiet -leaf -of_objects $net \
            -filter {DIRECTION == IN}]
        set fanout [llength $loads]
        if {$fanout > 20} {
            set load_names [lsort [get_property NAME $loads]]
            set signature "$fanout|[lindex $load_names 0]|[lindex $load_names 1]|[lindex $load_names end]"
            if {![info exists unique_nets($signature)] ||
                [string length [get_property NAME $net]] <
                [string length [get_property NAME $unique_nets($signature)]]} {
                set unique_nets($signature) $net
            }
        }
    }
    foreach signature [array names unique_nets] {
        set net $unique_nets($signature)
        set fanout [llength [get_pins -quiet -leaf -of_objects $net \
            -filter {DIRECTION == IN}]]
        lappend candidates [list $fanout $net]
    }
    set candidates [lsort -integer -decreasing -index 0 $candidates]

    set fh [open $outfile w]
    puts $fh "rank,net,fanout,driver_pin,driver_type,data_loads,ce_loads,reset_loads,clock_loads,lut_ram_loads,other_loads,main_load_cells"

    set rank 0
    foreach item [lrange $candidates 0 [expr {$max_nets - 1}]] {
        incr rank
        set fanout [lindex $item 0]
        set net [lindex $item 1]
        set net_name [get_property NAME $net]
        set drivers [get_pins -quiet -leaf -of_objects $net \
            -filter {DIRECTION == OUT}]
        set driver_pin ""
        set driver_type ""
        if {[llength $drivers] > 0} {
            set driver [lindex $drivers 0]
            set driver_pin [get_property NAME $driver]
            set driver_cells [get_cells -quiet -of_objects $driver]
            if {[llength $driver_cells] > 0} {
                set driver_type [get_property REF_NAME [lindex $driver_cells 0]]
            }
        }

        set data_loads 0
        set ce_loads 0
        set reset_loads 0
        set clock_loads 0
        set lut_ram_loads 0
        set other_loads 0
        catch {array unset load_cells}
        array set load_cells {}

        foreach load [get_pins -quiet -leaf -of_objects $net \
            -filter {DIRECTION == IN}] {
            set load_name [get_property NAME $load]
            set leaf [lindex [split $load_name "/"] end]
            set cells [get_cells -quiet -of_objects $load]
            set ref ""
            if {[llength $cells] > 0} {
                set ref [get_property REF_NAME [lindex $cells 0]]
                if {![info exists load_cells($ref)]} {
                    set load_cells($ref) 0
                }
                incr load_cells($ref)
            }

            if {$leaf eq "CE"} {
                incr ce_loads
            } elseif {$leaf eq "D" || [regexp {^(DI|S|WE|WEM|A|ADDR)} $leaf]} {
                incr data_loads
            } elseif {[regexp {^(CLR|PRE|R|S)} $leaf]} {
                incr reset_loads
            } elseif {$leaf eq "C" || $leaf eq "CLK" || $leaf eq "WCLK"} {
                incr clock_loads
            } elseif {[regexp {^(LUT|RAM|SRL)} $ref]} {
                incr lut_ram_loads
            } else {
                incr other_loads
            }
        }

        set load_summary {}
        foreach ref [lsort [array names load_cells]] {
            lappend load_summary "${ref}=$load_cells($ref)"
            if {[llength $load_summary] >= 6} {
                break
            }
        }

        puts $fh "$rank,[csv_quote $net_name],$fanout,[csv_quote $driver_pin],[csv_quote $driver_type],$data_loads,$ce_loads,$reset_loads,$clock_loads,$lut_ram_loads,$other_loads,[csv_quote [join $load_summary {;}]]"
    }
    close $fh
}

set xdc_file [file join $run_dir "hdec_top_${freq_mhz}mhz.xdc"]
write_text_file $xdc_file \
    "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_timing_atlas_${freq_mhz}mhz" -part $part_name
set_property source_mgmt_mode None [current_project]
add_files -fileset sources_1 $rtl_files
set_property file_type SystemVerilog [get_files $rtl_files]
set_property include_dirs [list $rtl_dir] [current_fileset]
add_files -fileset constrs_1 $xdc_file

synth_design -top hdec_top -part $part_name -mode out_of_context

report_timing_summary -max_paths 50 -nworst 1 \
    -file [file join $run_dir "timing_summary_top50.rpt"]
report_timing -delay_type max -sort_by slack -max_paths 200 -nworst 1 \
    -file [file join $run_dir "top200_setup_paths.rpt"]
export_top_paths_csv [file join $run_dir "top200_paths.csv"] 200

report_high_fanout_nets -max_nets 50 \
    -file [file join $run_dir "high_fanout_top50.rpt"]
export_high_fanout_csv [file join $run_dir "high_fanout_top50.csv"] 50
report_control_sets -verbose -file [file join $run_dir "control_sets.rpt"]
report_utilization -file [file join $run_dir "utilization.rpt"]
report_utilization -hierarchical -hierarchical_depth 2 \
    -file [file join $run_dir "utilization_hierarchical.rpt"]
report_power -file [file join $run_dir "power.rpt"]

set manifest_path [file join $run_dir "path_group_manifest.csv"]
set manifest_fh [open $manifest_path w]
puts $manifest_fh "group,from_cells,from_pins,to_cells,to_pins,report"

set group_dir [file join $run_dir "groups"]

report_path_group $manifest_fh "01_fsm_decode_to_uop_p1" \
    [list "*st_q_reg*" "*op_q_reg*" "*a_q_reg*" "*uop_p0_q_reg*"] \
    [list "*uop_p1_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "02_p1_vrf_capture_to_p2" \
    [list "*uop_p1_q_reg*" "*src0_q_reg*" "*hperm_a_q_reg*" \
        "*hcntadd_hv_q_reg*" "*i_vrf*"] \
    [list "*uop_p2_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "03a_p2_to_lane_result" \
    [list "*uop_p2_q_reg*" "*src0_q_reg*" "*hperm_a_q_reg*" "*i_vrf*"] \
    [list "*lane_result_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "03b_p2_to_lane_popcnt" \
    [list "*uop_p2_q_reg*" "*src0_q_reg*" "*i_vrf*"] \
    [list "*lane_popcnt_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "03c_p2_to_lane_clip" \
    [list "*uop_p2_q_reg*" "*hcntclip_word_q_reg*" "*i_vrf*"] \
    [list "*lane_clip_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "04a_lane_popcnt_to_hsim_total" \
    [list "*lane_popcnt_q_reg*"] \
    [list "*hsim_total_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "04b_hsim_total_to_hsim_total" \
    [list "*hsim_total_q_reg*"] \
    [list "*hsim_total_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "04c_hsim_total_to_hmatch_best" \
    [list "*hsim_total_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list D CE] 20 $group_dir

report_path_group $manifest_fh "04d_lane_popcnt_to_hmatch_best" \
    [list "*lane_popcnt_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list D CE] 20 $group_dir

report_path_group $manifest_fh "05a_hmatch_best_dist_D" \
    [list "*hsim_total_q_reg*" "*lane_popcnt_q_reg*" \
        "*hmatch_best_dist_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*"] [list D] 20 $group_dir

report_path_group $manifest_fh "05b_hmatch_best_dist_CE" \
    [list "*hsim_total_q_reg*" "*lane_popcnt_q_reg*" \
        "*hmatch_best_dist_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*"] [list CE] 20 $group_dir

report_path_group $manifest_fh "05c_hmatch_best_idx_D" \
    {} \
    [list "*hmatch_best_idx_q_reg*"] [list D] 20 $group_dir

report_path_group $manifest_fh "05d_hmatch_best_idx_CE" \
    [list "*hsim_total_q_reg*" "*lane_popcnt_q_reg*" \
        "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*" \
        "*hmatch_num_q_reg*"] \
    [list "*hmatch_best_idx_q_reg*"] [list CE] 20 $group_dir

report_path_group $manifest_fh "05e_hmatch_budget_to_best_CE" \
    [list "*hmatch_budget_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list CE] 20 $group_dir

report_path_group $manifest_fh "05f_hmatch_budget_feedback" \
    [list "*hmatch_budget_q_reg*"] \
    [list "*hmatch_budget_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "06_vrf_writeback" \
    [list "*lane_result_q_reg*" "*lane_clip_q_reg*" \
        "*hcntclip_word_q_reg*" "*uop_p3_q_reg*" "*a_q_reg*" \
        "*clr_cnt_q_reg*" "*clr_base_q_reg*"] \
    [list "*i_vrf*"] [list ALL] 20 $group_dir

report_path_group $manifest_fh "06b_vrf_ram_write" \
    [list "*lane_result_q_reg*" "*lane_clip_q_reg*" \
        "*hcntclip_word_q_reg*" "*uop_p3_q_reg*" "*a_q_reg*" \
        "*clr_cnt_q_reg*" "*clr_base_q_reg*"] \
    [list "*i_vrf/vrf_b*_reg_r*"] [list ALL] 20 $group_dir

report_path_group $manifest_fh "07_scalar_response" \
    [list "*hsim_total_q_reg*" "*hmatch_best_dist_q_reg*" \
        "*hmatch_best_idx_q_reg*" "*bk_q_reg*" "*i_vrf*" \
        "*response_valid_q_reg*"] \
    [list "*scalar_response_q_reg*" "*res_q_reg*"] [list D CE] 20 $group_dir

report_path_group $manifest_fh "08_fast_path_to_result_or_vrf" \
    [list "*a_q_reg*" "*op_q_reg*" "*vaddr*_q_reg*" \
        "*clr*_q_reg*" "*bk_q_reg*" "*i_vrf*"] \
    [list "*res_q_reg*" "*scalar_response_q_reg*" "*i_vrf*"] \
    [list ALL] 20 $group_dir

report_path_group $manifest_fh "09_control_CE_top50" \
    {} [list "*_reg*"] [list CE] 50 $group_dir

report_path_group $manifest_fh "10_reset_clear_enable_heavy" \
    [list "*st_q_reg*" "*op_q_reg*" "*clr*_q_reg*" "*uop*_q_reg*"] \
    [list "*_reg*"] [list RESET CE] 50 $group_dir

set fixed_dir [file join $run_dir "fixed_paths"]

report_path_group $manifest_fh "fixed_01_p2_control_to_lane_popcnt" \
    [list "*uop_p2_q_reg*use_*" "*uop_p2_q_reg*valid*"] \
    [list "*lane_popcnt_q_reg*"] [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_02_p2_control_to_lane_result" \
    [list "*uop_p2_q_reg*use_*" "*uop_p2_q_reg*valid*"] \
    [list "*lane_result_q_reg*"] [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_03_p2_control_to_lane_clip" \
    [list "*uop_p2_q_reg*use_*" "*uop_p2_q_reg*valid*"] \
    [list "*lane_clip_q_reg*"] [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_04_hsim_to_hmatch_CE" \
    [list "*hsim_total_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*"] [list CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_05_hsim_to_hmatch_D" \
    [list "*hsim_total_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*"] [list D] 50 $fixed_dir

report_path_group $manifest_fh "fixed_06_lane_popcnt_to_hsim" \
    [list "*lane_popcnt_q_reg*"] \
    [list "*hsim_total_q_reg*"] [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_07_lane_popcnt_to_hmatch" \
    [list "*lane_popcnt_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_08_hmatch_to_response" \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list "*scalar_response_q_reg*" "*res_q_reg*"] [list D CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_09_vrf_writeback_mux_control" \
    [list "*lane_result_q_reg*" "*lane_clip_q_reg*" \
        "*hcntclip_word_q_reg*" "*uop_p3_q_reg*" "*st_q_reg*" \
        "*clr*_q_reg*"] \
    [list "*i_vrf*"] [list ALL] 50 $fixed_dir

report_path_group $manifest_fh "fixed_10_vrf_ram_write" \
    [list "*lane_result_q_reg*" "*lane_clip_q_reg*" \
        "*hcntclip_word_q_reg*" "*uop_p3_q_reg*" "*st_q_reg*" \
        "*clr*_q_reg*" "*a_q_reg*"] \
    [list "*i_vrf/vrf_b*_reg_r*"] [list ALL] 50 $fixed_dir

report_path_group $manifest_fh "fixed_11_budget_to_hmatch_CE" \
    [list "*hmatch_budget_q_reg*"] \
    [list "*hmatch_best_dist_q_reg*" "*hmatch_best_idx_q_reg*"] \
    [list CE] 50 $fixed_dir

report_path_group $manifest_fh "fixed_12_budget_feedback" \
    [list "*hmatch_budget_q_reg*"] \
    [list "*hmatch_budget_q_reg*"] [list D CE] 50 $fixed_dir

close $manifest_fh

set summary_fh [open [file join $run_dir "run_summary.txt"] w]
puts $summary_fh "repo_root=$repo_root"
puts $summary_fh "commit=$commit_label"
puts $summary_fh "frequency_mhz=$freq_mhz"
puts $summary_fh "period_ns=$period_ns"
puts $summary_fh "part=$part_name"
puts $summary_fh "top=hdec_top"
puts $summary_fh "vivado_version=[version -short]"
set worst [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {$worst ne ""} {
    puts $summary_fh "wns=[get_property SLACK $worst]"
    puts $summary_fh "startpoint=[get_property STARTPOINT_PIN $worst]"
    puts $summary_fh "endpoint=[get_property ENDPOINT_PIN $worst]"
    puts $summary_fh "data_delay=[get_property DATAPATH_DELAY $worst]"
    puts $summary_fh "logic_delay=[get_property DATAPATH_LOGIC_DELAY $worst]"
    puts $summary_fh "route_delay=[get_property DATAPATH_NET_DELAY $worst]"
    puts $summary_fh "logic_levels=[get_property LOGIC_LEVELS $worst]"
    puts $summary_fh "main_cells=[path_cell_summary $worst]"
}
close $summary_fh

close_project
puts "INFO: Timing atlas complete for ${freq_mhz} MHz: $run_dir"
