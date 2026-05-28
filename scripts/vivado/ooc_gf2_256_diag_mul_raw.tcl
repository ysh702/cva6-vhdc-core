set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set rtl_file [file join $repo_dir core hdec rtl gf2_256_diag_mul_raw.sv]
set report_dir [file join $repo_dir reports vivado gf2_256_diag_mul_raw_ooc]
set build_dir [file join $repo_dir build vivado gf2_256_diag_mul_raw_ooc]
set part xc7z020clg400-2

file mkdir $report_dir
file mkdir $build_dir

set_part $part
read_verilog -sv $rtl_file

synth_design -top gf2_256_diag_mul_raw -part $part -mode out_of_context

create_clock -name clk_i -period 10.000 [get_ports clk_i]

report_utilization -file [file join $report_dir utilization_gf2_256_diag_mul_raw_ooc.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $report_dir utilization_gf2_256_diag_mul_raw_ooc_hier.rpt]
report_timing_summary -file [file join $report_dir timing_gf2_256_diag_mul_raw_ooc.rpt]
report_timing -max_paths 5 -path_type full_clock_expanded -file [file join $report_dir critical_paths_gf2_256_diag_mul_raw_ooc.rpt]
report_power -file [file join $report_dir power_gf2_256_diag_mul_raw_ooc.rpt]

set fh [open [file join $report_dir cell_usage_gf2_256_diag_mul_raw_ooc.rpt] w]
puts $fh "Cell usage after OOC synthesis"
puts $fh "=============================="
foreach ref [lsort -unique [get_property REF_NAME [get_cells -hierarchical]]] {
    set count [llength [get_cells -hierarchical -filter "REF_NAME == $ref"]]
    puts $fh [format "%-32s %8d" $ref $count]
}
close $fh

set sweep_fh [open [file join $report_dir clock_sweep_gf2_256_diag_mul_raw_ooc.rpt] w]
puts $sweep_fh "period_ns,wns_ns,tns_ns,estimated_fmax_mhz"
foreach period {10.000 7.500 5.000 4.000 3.000 2.500 2.000 1.500 1.000} {
    reset_timing
    create_clock -name clk_i -period $period [get_ports clk_i]
    update_timing
    set timing_paths [get_timing_paths -max_paths 1 -delay_type max]
    if {[llength $timing_paths] > 0} {
        set wns [get_property SLACK [lindex $timing_paths 0]]
    } else {
        set wns 0.0
    }
    if {[catch {set tns [get_property TNS [get_clocks clk_i]]}]} {
        set tns NA
    }
    set data_path [expr {$period - $wns}]
    if {$data_path > 0.0} {
        set fmax [expr {1000.0 / $data_path}]
    } else {
        set fmax 0.0
    }
    puts $sweep_fh [format "%.3f,%.3f,%s,%.2f" $period $wns $tns $fmax]
    report_timing_summary -max_paths 20 -file [file join $report_dir [format "timing_gf2_256_diag_mul_raw_ooc_%0.1fns.rpt" $period]]
}
close $sweep_fh

write_checkpoint -force [file join $build_dir gf2_256_diag_mul_raw_ooc_synth.dcp]
