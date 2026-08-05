# VV35 FULL implementation flow for Vivado 2024.2.
#
# The flow measures the standalone accelerator core, not a CVA6 or board top.
# It operates directly on the existing hdec_top and applies no parameter or
# define override, so the measured netlist is the unmodified VV35 design.
#
# Usage:
#   vivado -mode batch -source vv35_ecc_area_impl.tcl -tclargs \
#     <repo_root> <out_root> <top_module> <period_ns> <run_label>

if {$argc != 5} {
    error "Expected: <repo_root> <out_root> <top_module> <period_ns> <run_label>"
}

set repo_root  [file normalize [lindex $argv 0]]
set out_root   [file normalize [lindex $argv 1]]
set top_module [string trim [lindex $argv 2]]
set period_ns  [lindex $argv 3]
set run_label  [string trim [lindex $argv 4]]

if {![file isdirectory $repo_root]} {
    error "Repository root does not exist: $repo_root"
}
if {$top_module eq ""} {
    error "top_module must not be empty"
}
if {$run_label eq ""} {
    error "run_label must not be empty"
}
if {![string is double -strict $period_ns] || $period_ns <= 0.0} {
    error "period_ns must be a positive number, got '$period_ns'"
}

set part_name   "xc7z020clg400-2"
set script_dir  [file dirname [file normalize [info script]]]
set rtl_manifest [file join $script_dir "vv35_area_rtl_files.txt"]
set reports_dir [file join $out_root "reports"]
set dcp_dir     [file join $out_root "dcp"]
set work_dir    [file join $out_root "vivado"]

foreach dir [list $out_root $reports_dir $dcp_dir $work_dir] {
    file mkdir $dir
}

proc write_text_file {path contents} {
    set fh [open $path w]
    puts -nonewline $fh $contents
    close $fh
}

proc read_rtl_manifest {repo_root manifest_path} {
    if {![file exists $manifest_path]} {
        error "RTL manifest does not exist: $manifest_path"
    }
    set fh [open $manifest_path r]
    set contents [read $fh]
    close $fh

    set result [list]
    foreach raw_line [split $contents "\n"] {
        set line [string trim $raw_line]
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }
        set source_path [file normalize [file join $repo_root $line]]
        if {![file exists $source_path]} {
            error "Required RTL source does not exist: $source_path"
        }
        lappend result $source_path
    }
    if {[llength $result] == 0} {
        error "RTL manifest is empty: $manifest_path"
    }
    return $result
}

proc try_git {repo_root args} {
    set command [linsert $args 0 git -C $repo_root]
    if {[catch {exec {*}$command} output]} {
        return "UNKNOWN"
    }
    return [string trim $output]
}

proc timing_value {paths property_name} {
    if {[llength $paths] == 0} {
        return "NO_PATH"
    }
    return [get_property $property_name [lindex $paths 0]]
}

set rtl_files [read_rtl_manifest $repo_root $rtl_manifest]

set source_text ""
foreach source_path $rtl_files {
    append source_text "$source_path\n"
}
write_text_file [file join $reports_dir "source_files.txt"] $source_text

set xdc_file [file join $work_dir "${run_label}_${period_ns}ns.xdc"]
write_text_file $xdc_file \
    "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

set git_commit [try_git $repo_root rev-parse HEAD]
set git_status [try_git $repo_root status --porcelain=v1]
if {$git_status eq ""} {
    set git_state "CLEAN"
} elseif {$git_status eq "UNKNOWN"} {
    set git_state "UNKNOWN"
} else {
    set git_state "DIRTY"
}

set config_text ""
append config_text "run_label=$run_label\n"
append config_text "repo_root=$repo_root\n"
append config_text "git_commit=$git_commit\n"
append config_text "git_state=$git_state\n"
append config_text "part=$part_name\n"
append config_text "top=$top_module\n"
append config_text "configuration=FULL\n"
append config_text "parameter_overrides=NONE\n"
append config_text "period_ns=$period_ns\n"
append config_text "flow=synth_design,opt_design,place_design,phys_opt_design,route_design\n"
append config_text "vivado_version=[version -short]\n"
append config_text "rtl_manifest=$rtl_manifest\n"
write_text_file [file join $reports_dir "run_config.txt"] $config_text

create_project -in_memory "vv35_area_${run_label}" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design -top $top_module -part $part_name -mode out_of_context

write_checkpoint -force [file join $dcp_dir "01_synth.dcp"]
report_utilization \
    -file [file join $reports_dir "01_synth_utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "01_synth_utilization_hier.rpt"]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir "01_synth_timing_min_max.rpt"]

opt_design
write_checkpoint -force [file join $dcp_dir "02_opt.dcp"]

place_design
write_checkpoint -force [file join $dcp_dir "03_place.dcp"]
report_utilization \
    -file [file join $reports_dir "03_place_utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "03_place_utilization_hier.rpt"]

phys_opt_design
write_checkpoint -force [file join $dcp_dir "04_phys_opt.dcp"]
report_utilization \
    -file [file join $reports_dir "04_phys_opt_utilization.rpt"]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 50 \
    -file [file join $reports_dir "04_phys_opt_timing_min_max.rpt"]

route_design
write_checkpoint -force [file join $dcp_dir "05_route.dcp"]

report_utilization \
    -file [file join $reports_dir "05_route_utilization.rpt"]
report_utilization -hierarchical \
    -file [file join $reports_dir "05_route_utilization_hier.rpt"]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 100 \
    -file [file join $reports_dir "05_route_timing_min_max.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_setup_top200.rpt"]
report_timing -delay_type min -max_paths 200 -sort_by slack \
    -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_hold_top200.rpt"]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_internal_setup_top200.rpt"]
report_timing -delay_type min -max_paths 200 -sort_by slack \
    -from [all_registers] -to [all_registers] -input_pins -nets \
    -file [file join $reports_dir "05_route_timing_internal_hold_top200.rpt"]
report_route_status \
    -file [file join $reports_dir "05_route_status.rpt"]
report_drc \
    -file [file join $reports_dir "05_route_drc.rpt"]
report_methodology \
    -file [file join $reports_dir "05_route_methodology.rpt"]
report_clock_utilization \
    -file [file join $reports_dir "05_route_clock_utilization.rpt"]

set setup_paths [get_timing_paths -delay_type max -sort_by slack \
    -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -sort_by slack \
    -max_paths 1 -nworst 1]
set internal_setup_paths [get_timing_paths -delay_type max -sort_by slack \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1]
set internal_hold_paths [get_timing_paths -delay_type min -sort_by slack \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1]

set setup_wns [timing_value $setup_paths SLACK]
set hold_whs [timing_value $hold_paths SLACK]
set setup_delay [timing_value $setup_paths DATAPATH_DELAY]
set hold_delay [timing_value $hold_paths DATAPATH_DELAY]
set setup_endpoint [timing_value $setup_paths ENDPOINT_PIN]
set hold_endpoint [timing_value $hold_paths ENDPOINT_PIN]
set internal_setup_wns [timing_value $internal_setup_paths SLACK]
set internal_hold_whs [timing_value $internal_hold_paths SLACK]
set internal_setup_delay [timing_value $internal_setup_paths DATAPATH_DELAY]
set internal_hold_delay [timing_value $internal_hold_paths DATAPATH_DELAY]
set internal_setup_endpoint [timing_value $internal_setup_paths ENDPOINT_PIN]
set internal_hold_endpoint [timing_value $internal_hold_paths ENDPOINT_PIN]

if {$internal_setup_wns eq "NO_PATH"} {
    set internal_fmax_est "NO_PATH"
} else {
    set internal_fmax_est [format "%.3f" \
        [expr {1000.0 / ($period_ns - $internal_setup_wns)}]]
}

set summary $config_text
append summary "route_status=[get_property ROUTE_STATUS [current_design]]\n"
append summary "setup_wns_ns=$setup_wns\n"
append summary "setup_data_delay_ns=$setup_delay\n"
append summary "setup_endpoint=$setup_endpoint\n"
append summary "hold_whs_ns=$hold_whs\n"
append summary "hold_data_delay_ns=$hold_delay\n"
append summary "hold_endpoint=$hold_endpoint\n"
append summary "internal_setup_wns_ns=$internal_setup_wns\n"
append summary "internal_setup_data_delay_ns=$internal_setup_delay\n"
append summary "internal_setup_endpoint=$internal_setup_endpoint\n"
append summary "internal_hold_whs_ns=$internal_hold_whs\n"
append summary "internal_hold_data_delay_ns=$internal_hold_delay\n"
append summary "internal_hold_endpoint=$internal_hold_endpoint\n"
append summary "internal_fmax_est_mhz=$internal_fmax_est\n"
append summary "synth_utilization=[file join $reports_dir 01_synth_utilization.rpt]\n"
append summary "synth_hierarchy=[file join $reports_dir 01_synth_utilization_hier.rpt]\n"
append summary "route_utilization=[file join $reports_dir 05_route_utilization.rpt]\n"
append summary "route_hierarchy=[file join $reports_dir 05_route_utilization_hier.rpt]\n"
append summary "route_setup_report=[file join $reports_dir 05_route_timing_setup_top200.rpt]\n"
append summary "route_hold_report=[file join $reports_dir 05_route_timing_hold_top200.rpt]\n"
append summary "route_checkpoint=[file join $dcp_dir 05_route.dcp]\n"
append summary "ooc_timing_note=Use internal register-to-register timing as the standalone core timing evidence; package IO paths are not placement-accurate in OOC mode.\n"
write_text_file [file join $reports_dir "run_summary.txt"] $summary

close_project
