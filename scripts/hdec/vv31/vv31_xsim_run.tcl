if {$argc != 7} {
    error [concat \
        "Expected: <rtl_repo_root> <tb_repo_root> <out_root> <test_name>" \
        "<test_top> <test_file_relative_to_tb_root> <vector_dir>" \
    ]
}

set rtl_repo_root [file normalize [lindex $argv 0]]
set tb_repo_root  [file normalize [lindex $argv 1]]
set out_root      [file normalize [lindex $argv 2]]
set test_name     [lindex $argv 3]
set test_top      [lindex $argv 4]
set test_file     [file normalize [file join $tb_repo_root [lindex $argv 5]]]
set vector_dir    [file normalize [lindex $argv 6]]
set script_dir    [file dirname [file normalize [info script]]]
source [file join $script_dir "vv31_rtl_files.tcl"]

proc vv31_tool_exit_code {catch_code options} {
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

proc vv31_write_tool_status {path xvlog_exit xelab_exit xsim_exit} {
    set fh [open $path w]
    puts $fh "{"
    puts $fh "  \"xvlog\": $xvlog_exit,"
    puts $fh "  \"xelab\": $xelab_exit,"
    puts $fh "  \"xsim\": $xsim_exit"
    puts $fh "}"
    close $fh
}

set common_packages [vv31_common_packages $tb_repo_root]
set source_files [concat \
    [vv31_rtl_files $rtl_repo_root] \
    $common_packages \
    [list $test_file] \
]
vv31_require_sources $source_files

set run_dir [file join $out_root "xsim_$test_name"]
file mkdir $run_dir
foreach vector_file [glob -nocomplain -directory $vector_dir "*"] {
    if {[file isfile $vector_file]} {
        file copy -force $vector_file [file join $run_dir [file tail $vector_file]]
    }
}
cd $run_dir

set source_manifest [file join $run_dir "compiled_sources.txt"]
set sf [open $source_manifest w]
foreach source_file $source_files {
    puts $sf [file normalize $source_file]
}
close $sf

set tool_status_file [file join $run_dir "tool_status.json"]
set xvlog_exit -1
set xelab_exit -1
set xsim_exit -1
vv31_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit

set caught [catch {exec xvlog.bat -sv {*}$source_files 2>@1} output options]
set xvlog_exit [vv31_tool_exit_code $caught $options]
puts $output
vv31_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xvlog failed with exit code $xvlog_exit"
}

set caught [catch {exec xelab.bat $test_top -s $test_top 2>@1} output options]
set xelab_exit [vv31_tool_exit_code $caught $options]
puts $output
vv31_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xelab failed with exit code $xelab_exit"
}

set sim_tcl [file join $run_dir "run_all.tcl"]
set sim_fh [open $sim_tcl w]
puts $sim_fh "run all"
puts $sim_fh "quit"
close $sim_fh

set caught [catch {
    exec xsim.bat $test_top -tclbatch $sim_tcl 2>@1
} output options]
set xsim_exit [vv31_tool_exit_code $caught $options]
puts $output
vv31_write_tool_status $tool_status_file $xvlog_exit $xelab_exit $xsim_exit
if {$caught != 0} {
    error "xsim failed with exit code $xsim_exit"
}
