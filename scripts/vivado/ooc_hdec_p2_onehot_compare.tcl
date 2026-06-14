# Vivado 2024.2 OOC comparison sweep for HDEC P2 implementations.
#
# Usage:
#   vivado -mode batch -source scripts/vivado/ooc_hdec_p2_onehot_compare.tcl \
#     -tclargs <repo_root> <output_root> <version_label>

if {$argc != 3} {
    error "Expected: <repo_root> <output_root> <version_label>"
}

set repo_root    [file normalize [lindex $argv 0]]
set out_root     [file normalize [lindex $argv 1]]
set version_label [lindex $argv 2]
set rtl_dir      [file join $repo_root "core" "hdec" "rtl"]
set part_name    "xc7z020clg400-2"

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
]

foreach optional_file [list "hdec_lane_p2_local.sv" "hdec_p2_lane_slice.sv"] {
    set optional_path [file join $rtl_dir $optional_file]
    if {[file exists $optional_path]} {
        lappend rtl_files $optional_path
    }
}
lappend rtl_files [file join $rtl_dir "hdec_top.sv"]

proc write_text_file {path text} {
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
}

proc maybe_report {command args outfile} {
    set cmd [concat [list $command] $args [list -file $outfile]]
    if {[catch {uplevel 1 $cmd} msg]} {
        write_text_file $outfile "Command failed: $cmd\n$msg\n"
        puts "WARN: $cmd failed: $msg"
    }
}

proc report_matching_cells {outfile patterns} {
    set fh [open $outfile w]
    puts $fh "pattern|cell|ref_name|q_net|fanout"

    foreach pattern $patterns {
        set cells [get_cells -hier -quiet -filter "NAME =~ $pattern"]
        puts $fh "# pattern=$pattern count=[llength $cells]"
        foreach cell $cells {
            set cell_name [get_property NAME $cell]
            set ref_name [get_property REF_NAME $cell]
            set q_pins [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
            set q_net ""
            set fanout 0
            if {[llength $q_pins] > 0} {
                set nets [get_nets -quiet -of_objects $q_pins]
                if {[llength $nets] > 0} {
                    set q_net [get_property NAME [lindex $nets 0]]
                    set loads [get_pins -quiet -leaf -of_objects [lindex $nets 0] \
                        -filter {DIRECTION == IN}]
                    set fanout [llength $loads]
                }
            }
            puts $fh "$pattern|$cell_name|$ref_name|$q_net|$fanout"
        }
    }
    close $fh
}

proc report_ctrl_loads {outfile} {
    set fh [open $outfile w]
    puts $fh "cell|q_net|fanout|load_pin"

    set cells [get_cells -hier -quiet -filter {NAME =~ *p2_lane_ctrl_q_reg*}]
    foreach cell $cells {
        set cell_name [get_property NAME $cell]
        set q_pins [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
        if {[llength $q_pins] == 0} {
            continue
        }
        set nets [get_nets -quiet -of_objects $q_pins]
        if {[llength $nets] == 0} {
            continue
        }
        set net [lindex $nets 0]
        set net_name [get_property NAME $net]
        set loads [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]
        set fanout [llength $loads]
        if {$fanout == 0} {
            puts $fh "$cell_name|$net_name|0|"
        } else {
            foreach load $loads {
                puts $fh "$cell_name|$net_name|$fanout|[get_property NAME $load]"
            }
        }
    }
    close $fh
}

proc run_ooc {freq_mhz period_ns} {
    global repo_root rtl_dir out_root version_label part_name rtl_files

    set run_dir [file join $out_root "${freq_mhz}mhz"]
    file mkdir $run_dir

    set xdc_file [file join $run_dir "hdec_top_${freq_mhz}mhz.xdc"]
    write_text_file $xdc_file \
        "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

    create_project -in_memory "hdec_${version_label}_${freq_mhz}mhz" -part $part_name
    set_property source_mgmt_mode None [current_project]

    add_files -fileset sources_1 $rtl_files
    set_property file_type SystemVerilog [get_files $rtl_files]
    set_property include_dirs [list $rtl_dir] [current_fileset]
    add_files -fileset constrs_1 $xdc_file

    synth_design -top hdec_top -part $part_name -mode out_of_context

    report_timing_summary -file [file join $run_dir "timing_summary.rpt"]
    report_timing -max_paths 10 -delay_type max -sort_by slack \
        -file [file join $run_dir "critical_paths.rpt"]
    report_utilization -file [file join $run_dir "utilization.rpt"]
    report_power -file [file join $run_dir "power.rpt"]
    maybe_report report_high_fanout_nets [list -fanout_greater_than 20] \
        [file join $run_dir "high_fanout_nets.rpt"]
    maybe_report report_control_sets [list] \
        [file join $run_dir "control_sets.rpt"]

    report_matching_cells [file join $run_dir "netlist_cells.rpt"] [list \
        "*p2_lane_ctrl_q_reg*" \
        "*uop_p2_q_reg*" \
        "*lane_popcnt_q_reg*" \
        "*lane_pop7_q*" \
        "*lane_result_q_reg*" \
        "*lane_clip_q_reg*" \
    ]
    report_ctrl_loads [file join $run_dir "p2_lane_ctrl_loads.rpt"]

    set summary_file [file join $run_dir "run_summary.txt"]
    set fh [open $summary_file w]
    puts $fh "version_label=$version_label"
    puts $fh "repo_root=$repo_root"
    puts $fh "freq_mhz=$freq_mhz"
    puts $fh "period_ns=$period_ns"
    puts $fh "part=$part_name"
    puts $fh "top=hdec_top"
    puts $fh "vivado_version=[version -short]"
    puts $fh "p2_lane_ctrl_cell_count=[llength [get_cells -hier -quiet -filter {NAME =~ *p2_lane_ctrl_q_reg*}]]"

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
    puts "INFO: Running $version_label at ${freq_mhz} MHz (${period_ns} ns)"
    run_ooc $freq_mhz $period_ns
}

puts "INFO: OOC sweep complete for $version_label. Reports: $out_root"
