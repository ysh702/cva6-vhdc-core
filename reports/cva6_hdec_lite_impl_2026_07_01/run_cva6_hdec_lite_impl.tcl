set root "E:/HDEC/cva6-vhdc-core/tmp/hdec_v15_pointmul_worktree"
set report_root "$root/reports/cva6_hdec_lite_impl_2026_07_01"
set run_dir "$report_root/impl_zynq7020_lite_bufg"
file mkdir $run_dir

set_param general.maxThreads 8
create_project cva6_hdec_lite_impl $run_dir -force -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property include_dirs [list \
  $root/core/include \
  $root/core \
  $root/core/cvxif_example/include \
  $root/core/hdec/rtl \
  $root/vendor/pulp-platform/axi/include \
  $root/vendor/pulp-platform/common_cells/include \
  $root/core/cvfpu/src/common_cells/include \
  $root/core/cache_subsystem/hpdcache/rtl/include] [current_fileset]

set initial [list \
  $root/core/include/config_pkg.sv \
  $report_root/cv64a6_hdec_lite_config_pkg.sv \
  $root/vendor/pulp-platform/axi/src/axi_pkg.sv \
  $root/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv \
  $root/core/include/riscv_pkg.sv \
  $root/core/include/ariane_pkg.sv \
  $root/core/include/wt_cache_pkg.sv \
  $root/core/include/std_cache_pkg.sv \
  $root/core/include/build_config_pkg.sv \
  $root/corev_apu/tb/ariane_axi_pkg.sv \
  $root/corev_apu/tb/axi_intf.sv \
  $root/corev_apu/register_interface/src/reg_intf.sv \
  $root/corev_apu/tb/ariane_soc_pkg.sv \
  $root/corev_apu/riscv-dbg/src/dm_pkg.sv \
  $root/corev_apu/tb/ariane_axi_soc_pkg.sv \
  $root/corev_apu/src/ariane.sv]
read_verilog -sv $initial

array set seen {}
foreach f $initial { set seen([file normalize $f]) 1 }
set fp [open "$report_root/flist_lite_sources.txt" r]
set flist_text [read $fp]
close $fp
set rest {}
foreach f [regexp -all -inline {[^ \r\n\t]+} $flist_text] {
  set nf [file normalize $f]
  if {![info exists seen($nf)]} {
    lappend rest $f
    set seen($nf) 1
  }
}
read_verilog -sv $rest
read_verilog -sv [list $report_root/cva6_hdec_lite_impl_wrapper.sv]
read_xdc $report_root/cva6_hdec_lite_impl.xdc

set_property top cva6_hdec_lite_impl_wrapper [current_fileset]
update_compile_order -fileset sources_1

synth_design -top cva6_hdec_lite_impl_wrapper -part xc7z020clg400-2 -flatten_hierarchy rebuilt -retiming
write_checkpoint -force $run_dir/post_synth.dcp
report_utilization -file $run_dir/utilization_post_synth.rpt
report_utilization -hierarchical -hierarchical_depth 8 -file $run_dir/utilization_hier_post_synth.rpt
report_clock_utilization -file $run_dir/clock_utilization_post_synth.rpt
report_timing_summary -delay_type max -max_paths 20 -file $run_dir/timing_post_synth.rpt
report_high_fanout_nets -timing -load_types -max_nets 50 -file $run_dir/high_fanout_post_synth.rpt
check_timing -file $run_dir/check_timing_post_synth.rpt

set blackboxes [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]
set fp_bb [open "$run_dir/blackboxes_post_synth.txt" w]
puts $fp_bb "blackbox_count=[llength $blackboxes]"
foreach c $blackboxes { puts $fp_bb $c }
close $fp_bb
if {[llength $blackboxes] > 0} {
  puts "ERROR: black boxes remain after synthesis."
  exit 2
}

opt_design
write_checkpoint -force $run_dir/post_opt.dcp
report_timing_summary -delay_type max -max_paths 20 -file $run_dir/timing_post_opt.rpt

place_design
write_checkpoint -force $run_dir/post_place.dcp
report_utilization -file $run_dir/utilization_post_place.rpt
report_utilization -hierarchical -hierarchical_depth 8 -file $run_dir/utilization_hier_post_place.rpt
report_clock_utilization -file $run_dir/clock_utilization_post_place.rpt
report_timing_summary -delay_type max -max_paths 20 -file $run_dir/timing_post_place.rpt
report_high_fanout_nets -timing -load_types -max_nets 50 -file $run_dir/high_fanout_post_place.rpt

phys_opt_design
write_checkpoint -force $run_dir/post_phys_opt.dcp
report_timing_summary -delay_type max -max_paths 20 -file $run_dir/timing_post_phys_opt.rpt

route_design
write_checkpoint -force $run_dir/post_route.dcp
report_utilization -file $run_dir/utilization_post_route.rpt
report_utilization -hierarchical -hierarchical_depth 8 -file $run_dir/utilization_hier_post_route.rpt
report_clock_utilization -file $run_dir/clock_utilization_post_route.rpt
report_timing_summary -delay_type max -max_paths 50 -file $run_dir/timing_post_route.rpt
report_high_fanout_nets -timing -load_types -max_nets 50 -file $run_dir/high_fanout_post_route.rpt
report_power -file $run_dir/power_post_route.rpt
report_design_analysis -congestion -file $run_dir/design_analysis_congestion_post_route.rpt
report_methodology -file $run_dir/methodology_post_route.rpt

exit
