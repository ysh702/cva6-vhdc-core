# Reuse the VV30 random-K PMUL contract against the independent dual wrapper.
# The RTL and wrapper are compiled normally.  A testbench-only Boolean macro
# selects vv35_dual_accel_core_top instead of the default hdec_top instance.

if {$argc != 3} {
    error "Expected: <repo_root> <out_root> <vector_dir>"
}
set repo_root [file normalize [lindex $argv 0]]
set out_root [file normalize [lindex $argv 1]]
set vector_dir [file normalize [lindex $argv 2]]
set script_dir [file dirname [file normalize [info script]]]
source [file normalize [file join $script_dir ".." ".." "vv30" "vv30_rtl_files.tcl"]]

proc tool_exit_code {catch_code options} {
    if {$catch_code == 0} { return 0 }
    if {[dict exists $options -errorcode]} {
        set code [dict get $options -errorcode]
        if {[llength $code] >= 3 && [lindex $code 0] eq "CHILDSTATUS"} {
            return [lindex $code 2]
        }
    }
    return 1
}

set test_name "pmul_random_k"
set test_top [vv30_test_top $test_name]
set test_file [vv30_test_file $repo_root $test_name]
set wrapper_file [file join $repo_root "verif" "hdec" "vv35_eval" "dual" "vv35_dual_accel_core_top.sv"]
set ip_wrapper_file [file join $repo_root "verif" "hdec" "vv35_eval" "dual" "vv35_dual_ooc_ip_wrappers.sv"]
set run_dir [file join $out_root "xsim_dual_independent_pmul_random_k"]
file mkdir $run_dir
foreach vector_file [glob -nocomplain -directory $vector_dir "*.mem"] {
    file copy -force $vector_file [file join $run_dir [file tail $vector_file]]
}
cd $run_dir

set base_sources [concat \
    [vv30_rtl_files $repo_root] \
    [vv30_common_packages $repo_root]]
lappend base_sources $ip_wrapper_file
lappend base_sources $wrapper_file

set caught [catch {
    exec xvlog.bat -sv --define=VV35_DUAL_INDEPENDENT_IPS {*}$base_sources 2>@1
} output options]
puts $output
if {$caught != 0} { error "base xvlog failed: [tool_exit_code $caught $options]" }

set caught [catch {
    exec xvlog.bat -sv --define=VV35_DUAL_DUT $test_file 2>@1
} output options]
puts $output
if {$caught != 0} { error "testbench xvlog failed: [tool_exit_code $caught $options]" }

set caught [catch {exec xelab.bat $test_top -s $test_top 2>@1} output options]
puts $output
if {$caught != 0} { error "xelab failed: [tool_exit_code $caught $options]" }

set manifest_file [file join $vector_dir "vector_manifest.json"]
set mf [open $manifest_file r]
set manifest_text [read $mf]
close $mf
if {![regexp {"fields"[[:space:]]*:[[:space:]]*([0-9]+)} \
          $manifest_text -> random_square_count]} {
    error "Cannot read field count from $manifest_file"
}
set cf [open [file join $run_dir "random_count.mem"] w]
puts $cf [format "%08x" $random_square_count]
close $cf

set sim_tcl [file join $run_dir "run_all.tcl"]
set sf [open $sim_tcl w]
puts $sf "run all"
puts $sf "quit"
close $sf

set caught [catch {exec xsim.bat $test_top -tclbatch $sim_tcl 2>@1} output options]
puts $output
if {$caught != 0} { error "xsim failed: [tool_exit_code $caught $options]" }

if {[string first {[VV30:pmul_random_k] PASS} $output] < 0} {
    error "Dual PMUL run completed without the expected PASS marker"
}
puts "VV35_DUAL_INDEPENDENT_PMUL_RANDOM_K_PASS"
