if {($argc != 4) && ($argc != 5)} {
    error "Expected: <rtl_repo_root> <out_root> <test_name> <vector_dir> ?tb_repo_root?"
}

set rtl_repo_root [file normalize [lindex $argv 0]]
set out_root     [file normalize [lindex $argv 1]]
set test_name    [lindex $argv 2]
set vector_dir [file normalize [lindex $argv 3]]
set tb_repo_root $rtl_repo_root
if {$argc == 5} {
    set tb_repo_root [file normalize [lindex $argv 4]]
}
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir "vv30_rtl_files.tcl"]

proc vv30_tool_exit_code {catch_code options} {
    if {$catch_code == 0} {
        return 0
    }
    if {[dict exists $options -errorcode]} {
        set error_code [dict get $options -errorcode]
        if {([llength $error_code] >= 3)
            && ([lindex $error_code 0] eq "CHILDSTATUS")} {
            return [lindex $error_code 2]
        }
    }
    return 1
}

proc vv30_write_tool_status {path xvlog_exit xelab_exit xsim_exit} {
    set fh [open $path w]
    puts $fh "{"
    puts $fh "  \"xvlog\": $xvlog_exit,"
    puts $fh "  \"xelab\": $xelab_exit,"
    puts $fh "  \"xsim\": $xsim_exit"
    puts $fh "}"
    close $fh
}

set test_top  [vv30_test_top $test_name]
set test_file [vv30_test_file $tb_repo_root $test_name]
set run_dir   [file join $out_root "xsim_$test_name"]
file mkdir $run_dir
foreach vector_file [glob -nocomplain -directory $vector_dir "*.mem"] {
    file copy -force $vector_file [file join $run_dir [file tail $vector_file]]
}
cd $run_dir

set source_files [concat \
    [vv30_rtl_files $rtl_repo_root] \
    [vv30_common_packages $tb_repo_root] \
    [list $test_file] \
]

set tool_status_file [file join $run_dir "tool_status.json"]
set xvlog_exit -1
set xelab_exit -1
set xsim_exit -1

set caught [catch {exec xvlog.bat -sv {*}$source_files 2>@1} output options]
set xvlog_exit [vv30_tool_exit_code $caught $options]
puts $output
vv30_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xvlog failed with exit code $xvlog_exit"
}

set caught [catch {exec xelab.bat $test_top -s $test_top 2>@1} output options]
set xelab_exit [vv30_tool_exit_code $caught $options]
puts $output
vv30_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xelab failed with exit code $xelab_exit"
}

set sim_tcl [file join $run_dir "run_all.tcl"]
set fh [open $sim_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

set manifest_file [file join $vector_dir "vector_manifest.json"]
set manifest_text [read [set mf [open $manifest_file r]]]
close $mf
if {![regexp {"fields"[[:space:]]*:[[:space:]]*([0-9]+)} \
              $manifest_text -> random_square_count]} {
    error "Cannot read field count from $manifest_file"
}
set cf [open [file join $run_dir "random_count.mem"] w]
puts $cf [format "%08x" $random_square_count]
close $cf
set caught [catch {
    exec xsim.bat $test_top -tclbatch $sim_tcl 2>@1
} output options]
set xsim_exit [vv30_tool_exit_code $caught $options]
puts $output
vv30_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xsim failed with exit code $xsim_exit"
}
