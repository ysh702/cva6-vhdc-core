# Exact from-to query for the old P2 pop_q -> popcount path.
if {$argc != 2} {
    error "Expected: <repo_root> <out_root>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root  [file normalize [lindex $argv 1]]
set reports_dir [file join $out_root "reports" "p2_exact"]
set vivado_dir  [file join $out_root "vivado"]
set rtl_dir     [file join $repo_root "core" "hdec" "rtl"]
set part_name   "xc7z020clg400-2"
set period_ns   "5.000"

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

proc export_first_path {label outfile paths period_ns} {
    set fh [open $outfile w]
    puts $fh "label,slack_ns,data_path_delay_ns,logic_delay_ns,route_delay_ns,logic_levels,startpoint,endpoint,fmax_est_mhz"
    if {[llength $paths] == 0} {
        puts $fh "[csv_quote $label],NO_PATH,,,,,,,"
        close $fh
        return
    }
    set p [lindex $paths 0]
    set slack [get_property SLACK $p]
    set delay [get_property DATAPATH_DELAY $p]
    set logic [get_property DATAPATH_LOGIC_DELAY $p]
    set route [get_property DATAPATH_NET_DELAY $p]
    set levels [get_property LOGIC_LEVELS $p]
    set startpoint [get_property STARTPOINT_PIN $p]
    set endpoint [get_property ENDPOINT_PIN $p]
    set fmax [format "%.3f" [expr {1000.0 / ($period_ns - $slack)}]]
    puts $fh "[csv_quote $label],$slack,$delay,$logic,$route,$levels,[csv_quote $startpoint],[csv_quote $endpoint],$fmax"
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

set xdc_file [file join $vivado_dir "hdec_top_p2_exact_5ns.xdc"]
write_text_file $xdc_file "create_clock -name clk_i -period $period_ns \[get_ports clk_i\]\n"

create_project -in_memory "hdec_p2_exact" -part $part_name
set_property target_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file
synth_design -top hdec_top -part $part_name -mode out_of_context

set popq_cells [get_cells -hier -quiet -filter {NAME =~ *i_p2_pop_slice/pop_q_reg}]
set popq_pins  [get_pins -quiet -of_objects $popq_cells -filter {DIRECTION == OUT}]
set popcnt_cells [get_cells -hier -quiet -filter {NAME =~ *i_p2_pop_slice/popcount_q_o_reg*}]
set popcnt_d  [get_pins -quiet -of_objects $popcnt_cells -filter {NAME =~ */D}]
set popcnt_ce [get_pins -quiet -of_objects $popcnt_cells -filter {NAME =~ */CE}]
set popcnt_all [concat $popcnt_d $popcnt_ce]

set info "popq_cells=[llength $popq_cells]\npopq_pins=[llength $popq_pins]\npopcnt_cells=[llength $popcnt_cells]\npopcnt_d=[llength $popcnt_d]\npopcnt_ce=[llength $popcnt_ce]\n"
write_text_file [file join $reports_dir "p2_exact_manifest.txt"] $info

if {[llength $popq_pins] > 0 && [llength $popcnt_d] > 0} {
    report_timing -delay_type max -sort_by slack -max_paths 10 -nworst 1 -from $popq_pins -to $popcnt_d -input_pins -file [file join $reports_dir "popq_to_popcnt_D.rpt"]
    set paths_d [get_timing_paths -delay_type max -sort_by slack -max_paths 1 -nworst 1 -from $popq_pins -to $popcnt_d]
} else {
    set paths_d {}
    write_text_file [file join $reports_dir "popq_to_popcnt_D.rpt"] "No from/to matched.\n"
}

if {[llength $popq_pins] > 0 && [llength $popcnt_ce] > 0} {
    report_timing -delay_type max -sort_by slack -max_paths 10 -nworst 1 -from $popq_pins -to $popcnt_ce -input_pins -file [file join $reports_dir "popq_to_popcnt_CE.rpt"]
    set paths_ce [get_timing_paths -delay_type max -sort_by slack -max_paths 1 -nworst 1 -from $popq_pins -to $popcnt_ce]
} else {
    set paths_ce {}
    write_text_file [file join $reports_dir "popq_to_popcnt_CE.rpt"] "No from/to matched.\n"
}

if {[llength $popq_pins] > 0 && [llength $popcnt_all] > 0} {
    set paths_all [get_timing_paths -delay_type max -sort_by slack -max_paths 1 -nworst 1 -from $popq_pins -to $popcnt_all]
} else {
    set paths_all {}
}

export_first_path "pop_q_to_popcount_D" [file join $reports_dir "popq_to_popcnt_D.csv"] $paths_d $period_ns
export_first_path "pop_q_to_popcount_CE" [file join $reports_dir "popq_to_popcnt_CE.csv"] $paths_ce $period_ns
export_first_path "pop_q_to_popcount_any" [file join $reports_dir "popq_to_popcnt_any.csv"] $paths_all $period_ns

close_project
