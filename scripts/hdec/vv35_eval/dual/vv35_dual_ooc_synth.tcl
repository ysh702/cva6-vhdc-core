# Independently synthesize the HDC and ECC IPs, freeze both checkpoints, then
# integrate them under the existing dual command router without cross-IP logic
# optimization.

if {$argc != 3} {
    error "Expected: <repo_root> <out_root> <period_ns>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set period_ns [lindex $argv 2]

set part_name "xc7z020clg400-2"
set script_dir [file dirname [file normalize [info script]]]
set manifest [file join $script_dir "vv35_dual_rtl_files.txt"]
set wrapper_file [file join $repo_root "verif" "hdec" "vv35_eval" "dual" "vv35_dual_accel_core_top.sv"]
set ip_wrapper_file [file join $repo_root "verif" "hdec" "vv35_eval" "dual" "vv35_dual_ooc_ip_wrappers.sv"]
set ip_stub_file [file join $repo_root "verif" "hdec" "vv35_eval" "dual" "vv35_dual_ooc_ip_stubs.sv"]
set pkg_file [file join $repo_root "core" "hdec" "rtl" "hdec_pkg.sv"]
set resource_pkg_file [file join $repo_root "core" "hdec" "rtl" "hdec_resource_pkg.sv"]
set dcp_dir [file join $out_root "dcp"]
set netlist_dir [file join $out_root "netlist"]
set reports_dir [file join $out_root "reports"]
set work_dir [file join $out_root "work"]
foreach dir [list $out_root $dcp_dir $netlist_dir $reports_dir $work_dir] { file mkdir $dir }

proc write_text {path value} {
    set fh [open $path w]
    puts -nonewline $fh $value
    close $fh
}

set fh [open $manifest r]
set manifest_text [read $fh]
close $fh
set core_rtl_files [list]
foreach raw [split $manifest_text "\n"] {
    set line [string trim $raw]
    if {$line eq "" || [string match "#*" $line]} { continue }
    set source_path [file normalize [file join $repo_root $line]]
    if {$source_path eq $wrapper_file} { continue }
    if {![file exists $source_path]} { error "Missing RTL source: $source_path" }
    lappend core_rtl_files $source_path
}

set xdc_file [file join $work_dir "vv35_dual_ooc_${period_ns}ns.xdc"]
write_text $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

set flatten_mode "none"
set synth_directive "RuntimeOptimized"

proc synth_ip {repo_root out_root part_name xdc_file core_rtl_files ip_wrapper_file top_name tag flatten_mode synth_directive} {
    create_project -in_memory "vv35_ooc_${tag}" -part $part_name
    set_property target_language Verilog [current_project]
    set_property source_mgmt_mode None [current_project]
    read_verilog -sv $core_rtl_files
    read_verilog -sv $ip_wrapper_file
    read_xdc $xdc_file
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy $flatten_mode -directive $synth_directive
    write_checkpoint -force [file join $out_root dcp "${tag}.dcp"]
    write_edif -force [file join $out_root netlist "${top_name}.edf"]
    report_utilization -file [file join $out_root reports "${tag}_utilization.rpt"]
    report_utilization -hierarchical -file [file join $out_root reports "${tag}_utilization_hier.rpt"]
    close_project
}

synth_ip $repo_root $out_root $part_name $xdc_file $core_rtl_files \
    $ip_wrapper_file vv35_hdc_ip_top hdc_ip $flatten_mode $synth_directive
synth_ip $repo_root $out_root $part_name $xdc_file $core_rtl_files \
    $ip_wrapper_file vv35_ecc_ip_top ecc_ip $flatten_mode $synth_directive

create_project -in_memory "vv35_dual_independent_router" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv [list $pkg_file $resource_pkg_file]
read_verilog -sv $ip_stub_file
set_property verilog_define {VV35_DUAL_INDEPENDENT_IPS} [current_fileset]
read_verilog -sv $wrapper_file
read_xdc $xdc_file
synth_design -top vv35_dual_accel_core_top -part $part_name -mode out_of_context \
    -flatten_hierarchy none -directive Default
write_edif -force [file join $netlist_dir vv35_dual_accel_core_top.edf]
report_utilization -file [file join $reports_dir dual_router_utilization.rpt]
close_project

create_project -in_memory "vv35_dual_independent_linked" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_edif [list \
    [file join $netlist_dir vv35_dual_accel_core_top.edf] \
    [file join $netlist_dir vv35_hdc_ip_top.edf] \
    [file join $netlist_dir vv35_ecc_ip_top.edf]]
read_xdc $xdc_file
link_design -top vv35_dual_accel_core_top -part $part_name \
    -mode out_of_context

set hdc_cell [get_cells -quiet u_hdc]
set ecc_cell [get_cells -quiet u_ecc]
if {[llength $hdc_cell] != 1 || [llength $ecc_cell] != 1} {
    error "Independent accelerator IP cells were not preserved as unique instances"
}
set_property DONT_TOUCH true [get_cells u_hdc]
set_property DONT_TOUCH true [get_cells u_ecc]

set blackboxes [get_cells -hierarchical -quiet -filter {IS_BLACKBOX}]
if {[llength $blackboxes] != 0} {
    error "Integrated design still contains [llength $blackboxes] black boxes"
}

write_checkpoint -force [file join $dcp_dir "vv35_dual_independent_synth.dcp"]
report_utilization -file [file join $reports_dir "vv35_dual_independent_utilization.rpt"]
report_utilization -hierarchical -file [file join $reports_dir "vv35_dual_independent_utilization_hier.rpt"]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 50 -file [file join $reports_dir "vv35_dual_independent_timing_summary.rpt"]

set summary ""
append summary "vivado_version=[version -short]\n"
append summary "part=$part_name\n"
append summary "period_ns=$period_ns\n"
append summary "ip_flatten_hierarchy=$flatten_mode\n"
append summary "ip_synth_directive=$synth_directive\n"
append summary "cross_ip_optimization=disabled_by_frozen_ooc_checkpoints_and_dont_touch_cells\n"
append summary "integrated_blackbox_count=[llength $blackboxes]\n"
append summary "hdc_checkpoint=[file join $dcp_dir hdc_ip.dcp]\n"
append summary "ecc_checkpoint=[file join $dcp_dir ecc_ip.dcp]\n"
append summary "hdc_structural_netlist=[file join $netlist_dir vv35_hdc_ip_top.edf]\n"
append summary "ecc_structural_netlist=[file join $netlist_dir vv35_ecc_ip_top.edf]\n"
append summary "integrated_checkpoint=[file join $dcp_dir vv35_dual_independent_synth.dcp]\n"
write_text [file join $reports_dir "run_summary.txt"] $summary
close_project

puts "VV35_DUAL_INDEPENDENT_SYNTH_PASS output=$out_root"
