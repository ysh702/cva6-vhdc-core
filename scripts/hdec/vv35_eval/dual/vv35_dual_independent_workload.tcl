# RTL functional and cycle test for one K-233 PMUL running concurrently with
# 1632 four-class HMATCH searches on the independent ECC and HDC IPs.

if {$argc != 3} {
    error "Expected: <repo_root> <out_root> <vector_dir>"
}

set repo_root [file normalize [lindex $argv 0]]
set out_root [file normalize [lindex $argv 1]]
set vector_dir [file normalize [lindex $argv 2]]
set script_dir [file dirname [file normalize [info script]]]
set manifest [file join $script_dir vv35_dual_rtl_files.txt]
set ip_wrapper [file join $repo_root verif hdec vv35_eval dual vv35_dual_ooc_ip_wrappers.sv]
set dual_wrapper [file join $repo_root verif hdec vv35_eval dual vv35_dual_accel_core_top.sv]
set tb_file [file join $repo_root verif hdec vv35_eval gate tb_vv35_schedule_gate.sv]
set run_dir [file join $out_root xsim_dual_independent_workload]
file mkdir $run_dir

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

set source_files [list]
set fh [open $manifest r]
set manifest_text [read $fh]
close $fh
foreach raw [split $manifest_text "\n"] {
    set line [string trim $raw]
    if {$line eq "" || [string match "#*" $line]} { continue }
    set path [file normalize [file join $repo_root $line]]
    if {$path eq $dual_wrapper} { continue }
    lappend source_files $path
}
lappend source_files $ip_wrapper $dual_wrapper
lappend source_files \
    [file join $repo_root verif hdec vv31 common hdec_vv31_vectors_pkg.sv] \
    [file join $repo_root verif hdec vv31 common hdec_vv31_ref_pkg.sv] \
    [file join $repo_root verif hdec vv31 common hdec_vv31_driver_pkg.sv] \
    [file join $repo_root verif hdec vv31 common hdec_vv31_check_pkg.sv] \
    $tb_file

foreach source $source_files {
    if {![file exists $source]} { error "Missing source: $source" }
}
foreach vector_file [glob -nocomplain -directory $vector_dir "*.mem"] {
    file copy -force $vector_file [file join $run_dir [file tail $vector_file]]
}
file copy -force [file join $vector_dir vector_manifest.json] \
    [file join $run_dir vector_manifest.json]

cd $run_dir
set caught [catch {
    exec xvlog.bat -sv \
        --define=VV35_DUAL_INDEPENDENT_IPS \
        --define=VV35_DUAL_INDEPENDENT_DUT \
        {*}$source_files 2>@1
} output options]
puts $output
if {$caught != 0} { error "xvlog failed: [tool_exit_code $caught $options]" }

set top tb_vv35_schedule_gate
set caught [catch {
    exec xelab.bat $top --timescale 1ns/1ps -s $top 2>@1
} output options]
puts $output
if {$caught != 0} { error "xelab failed: [tool_exit_code $caught $options]" }

set run_tcl [file join $run_dir run_all.tcl]
set rf [open $run_tcl w]
puts $rf "run all"
puts $rf "quit"
close $rf

set vector_forward [string map {\\ /} $vector_dir]
set response_file [file join $run_dir xsim_args.f]
set af [open $response_file w]
puts $af "-testplusarg"
puts $af "SCENARIO=INDEPENDENT"
puts $af "-testplusarg"
puts $af "TASK_COUNT=1632"
puts $af "-testplusarg"
puts $af "WINDOW_CYCLES=190944"
puts $af "-testplusarg"
puts $af "PMUL_WAIT_CYCLES=146908"
puts $af "-testplusarg"
puts $af "VV31_VECTOR_DIR=$vector_forward"
close $af
set caught [catch {
    exec xsim.bat $top -f $response_file -tclbatch $run_tcl 2>@1
} output options]
puts $output
if {$caught != 0} { error "xsim failed: [tool_exit_code $caught $options]" }

set pass_marker {[VV35:GATE_SCHEDULE] PASS scenario=INDEPENDENT}
if {[string first $pass_marker $output] < 0} {
    error "Independent workload completed without the expected PASS marker"
}
if {![regexp {window_cycles=190944} $output]} {
    error "Independent workload did not preserve the 190944-cycle contract"
}
if {![regexp {hmatch_completed=1632} $output]} {
    error "Independent workload did not complete 1632 HMATCH searches"
}
puts "VV35_DUAL_INDEPENDENT_WORKLOAD_PASS cycles=190944 hmatch=1632 pmul=1"
