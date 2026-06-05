# Vivado 2024.2 OOC synthesis sweep for HDEC P2 lane-local control.
# Run from the repository root with:
#   vivado -mode batch -source scripts/vivado/ooc_hdec_p2_lane_local_control_v1.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir ".." ".."]]
set rtl_dir    [file join $repo_root "core" "hdec" "rtl"]
set out_root   [file join $repo_root "reports" "vivado" "ooc_hdc_hdcu_p2_lane_local_control_v1"]
set part_name  "xc7z020clg400-2"

file mkdir $out_root

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
    [file join $rtl_dir "hdec_lane_p2_local.sv"] \
    [file join $rtl_dir "hdec_top.sv"] \
]

proc write_text_file {path text} {
    set fh [open $path w]
    puts $fh $text
    close $fh
}

proc maybe_report {command args outfile} {
    set cmd [concat [list $command] $args [list -file $outfile]]
    if {[catch {uplevel 1 $cmd} msg]} {
        write_text_file $outfile "Command failed: $cmd\n$msg"
        puts "WARN: $cmd failed: $msg"
    }
}

proc run_ooc {freq_mhz period_ns} {
    global repo_root rtl_dir out_root part_name rtl_files

    set run_dir [file join $out_root "${freq_mhz}mhz"]
    file mkdir $run_dir

    set xdc_file [file join $run_dir "hdec_top_${freq_mhz}mhz.xdc"]
    write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

    create_project -in_memory "hdec_ooc_${freq_mhz}mhz" -part $part_name
    set_property source_mgmt_mode None [current_project]

    add_files -fileset sources_1 $rtl_files
    set_property file_type SystemVerilog [get_files $rtl_files]
    set_property include_dirs [list $rtl_dir] [current_fileset]
    add_files -fileset constrs_1 $xdc_file

    synth_design -top hdec_top -part $part_name -mode out_of_context

    report_timing_summary -file [file join $run_dir "timing_summary.rpt"]
    report_timing -max_paths 10 -delay_type max -sort_by slack -file [file join $run_dir "critical_paths.rpt"]
    report_utilization -file [file join $run_dir "utilization.rpt"]
    report_power -file [file join $run_dir "power.rpt"]
    maybe_report report_high_fanout_nets [list -fanout_greater_than 50] [file join $run_dir "high_fanout_nets.rpt"]
    maybe_report report_control_sets [list] [file join $run_dir "control_sets.rpt"]

    set summary_file [file join $run_dir "run_summary.txt"]
    set fh [open $summary_file w]
    puts $fh "freq_mhz=$freq_mhz"
    puts $fh "period_ns=$period_ns"
    puts $fh "part=$part_name"
    puts $fh "top=hdec_top"
    puts $fh "vivado_version=[version -short]"
    if {[catch {set path [lindex [get_timing_paths -max_paths 1 -delay_type max] 0]} msg]} {
        puts $fh "timing_path_error=$msg"
    } elseif {$path ne ""} {
        puts $fh "wns=[get_property SLACK $path]"
        puts $fh "startpoint=[get_property STARTPOINT_PIN $path]"
        puts $fh "endpoint=[get_property ENDPOINT_PIN $path]"
        puts $fh "data_path_delay=[get_property DATAPATH_DELAY $path]"
        puts $fh "logic_delay=[get_property DATAPATH_LOGIC_DELAY $path]"
        puts $fh "route_delay=[get_property DATAPATH_NET_DELAY $path]"
        puts $fh "logic_levels=[get_property LOGIC_LEVELS $path]"
    }
    close $fh

    close_project
}

set sweep {
    {100 10.000}
    {125 8.000}
    {150 6.667}
    {175 5.714}
    {200 5.000}
}

foreach item $sweep {
    set freq_mhz [lindex $item 0]
    set period_ns [lindex $item 1]
    puts "INFO: Running hdec_top OOC synthesis at ${freq_mhz} MHz (${period_ns} ns)"
    run_ooc $freq_mhz $period_ns
}

puts "INFO: HDEC OOC sweep complete. Reports: $out_root"
