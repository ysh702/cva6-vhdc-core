proc required_env {name} {
    if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
        error "Required environment variable $name is not set"
    }
    return [string trim $::env($name)]
}

proc optional_env {name default_value} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default_value
}

set repo_root [file normalize [required_env HDEC_REPO_ROOT]]
set out_dir [file normalize [required_env HDEC_OUT_DIR]]
set vrf_mode [string toupper [optional_env HDEC_VRF_MODE REG_VRF]]
set target_libs [required_env HDEC_TARGET_LIBS]
set link_libs [optional_env HDEC_LINK_LIBS $target_libs]
set sdc_file [file join $repo_root verif hdec vv35_eval asic hdec_top_200mhz.sdc]
set filelist [file join $repo_root verif hdec vv35_eval asic hdec_vv35_rtl.f]

file mkdir $out_dir
file mkdir [file join $out_dir work]
file mkdir [file join $out_dir reports]
file mkdir [file join $out_dir netlist]

set search_dirs [list $repo_root]
foreach lib $target_libs {
    lappend search_dirs [file dirname [file normalize $lib]]
}
set_app_var search_path [concat $search_path $search_dirs]
set_app_var target_library $target_libs
set_app_var link_library [concat "*" $target_libs $link_libs]
define_design_lib WORK -path [file join $out_dir work]

set rtl_files {}
set fh [open $filelist r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {
        continue
    }
    if {[string match "*hdec_vrf_64x256.sv" $line]} {
        if {$vrf_mode eq "REG_VRF"} {
            lappend rtl_files [file join $repo_root $line]
        } elseif {$vrf_mode eq "BLACKBOX_VRF"} {
            lappend rtl_files [file join $repo_root verif hdec vv35_eval asic hdec_vrf_64x256_blackbox.sv]
        } elseif {$vrf_mode eq "SRAM_MACRO_VRF"} {
            lappend rtl_files [file normalize [required_env HDEC_SRAM_ADAPTER_RTL]]
        } else {
            error "Unsupported HDEC_VRF_MODE=$vrf_mode"
        }
    } else {
        lappend rtl_files [file join $repo_root $line]
    }
}
close $fh

foreach rtl $rtl_files {
    if {![file exists $rtl]} {
        error "Missing RTL source $rtl"
    }
}

analyze -format sverilog -library WORK $rtl_files
elaborate hdec_top -library WORK
current_design hdec_top
if {![link]} {
    error "Link failed for hdec_top"
}
uniquify

if {$vrf_mode eq "SRAM_MACRO_VRF"} {
    set sram_macro_name [required_env HDEC_SRAM_MACRO_NAME]
    set sram_cells [get_cells -hierarchical -filter "ref_name == $sram_macro_name"]
    set sram_count [sizeof_collection $sram_cells]
    if {$sram_count != 4} {
        error "Expected exactly four $sram_macro_name instances, found $sram_count"
    }
}

if {[info exists ::env(HDEC_OPERATING_CONDITION)] &&
    [string trim $::env(HDEC_OPERATING_CONDITION)] ne ""} {
    set_operating_conditions $::env(HDEC_OPERATING_CONDITION)
}

source $sdc_file
redirect -file [file join $out_dir reports check_design_precompile.rpt] {check_design}
redirect -file [file join $out_dir reports check_timing_precompile.rpt] {check_timing}
redirect -file [file join $out_dir reports units.rpt] {report_units}
redirect -file [file join $out_dir reports references_precompile.rpt] {report_reference -hierarchy}

set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
compile_ultra -no_autoungroup -no_boundary_optimization
change_names -rules verilog -hierarchy

redirect -file [file join $out_dir reports qor.rpt] {report_qor}
redirect -file [file join $out_dir reports area.rpt] {report_area -hierarchy}
if {[catch {
    redirect -file [file join $out_dir reports area_physical.rpt] {
        report_area -physical -hierarchy
    }
} area_physical_error]} {
    set physical_note [open [file join $out_dir reports area_physical_unavailable.txt] w]
    puts $physical_note $area_physical_error
    close $physical_note
}
redirect -file [file join $out_dir reports timing_max.rpt] {report_timing -delay_type max -max_paths 100 -nets -transition_time -capacitance}
redirect -file [file join $out_dir reports timing_min.rpt] {report_timing -delay_type min -max_paths 100 -nets -transition_time -capacitance}
redirect -file [file join $out_dir reports constraints.rpt] {report_constraint -all_violators}
redirect -file [file join $out_dir reports clocks.rpt] {report_clock}
redirect -file [file join $out_dir reports check_design_postcompile.rpt] {check_design}
redirect -file [file join $out_dir reports check_timing_postcompile.rpt] {check_timing}
redirect -file [file join $out_dir reports references_postcompile.rpt] {report_reference -hierarchy}

write -format ddc -hierarchy -output [file join $out_dir netlist hdec_top.ddc]
write -format verilog -hierarchy -output [file join $out_dir netlist hdec_top_mapped.v]
write_sdf -version 3.0 [file join $out_dir netlist hdec_top_mapped.sdf]
write_sdc [file join $out_dir netlist hdec_top_mapped.sdc]

set manifest [open [file join $out_dir synth_context.txt] w]
puts $manifest "top=hdec_top"
puts $manifest "vrf_mode=$vrf_mode"
puts $manifest "target_library=$target_libs"
puts $manifest "link_library=$link_libs"
puts $manifest "operating_condition=[optional_env HDEC_OPERATING_CONDITION NOT_SET]"
puts $manifest "period_ns=[optional_env HDEC_PERIOD_NS 5.000]"
if {$vrf_mode eq "REG_VRF"} {
    puts $manifest "qualification=PRE_LAYOUT_COMPLETE_REGISTER_VRF"
} elseif {$vrf_mode eq "BLACKBOX_VRF"} {
    puts $manifest "qualification=PRE_LAYOUT_LOGIC_CORE_EXCLUDING_VRF_SRAM"
} else {
    puts $manifest "qualification=PRE_LAYOUT_COMPLETE_SRAM_MACRO_VRF"
    puts $manifest "sram_macro_name=[required_env HDEC_SRAM_MACRO_NAME]"
}
puts $manifest "rtl_files=[join $rtl_files ,]"
close $manifest

quit
