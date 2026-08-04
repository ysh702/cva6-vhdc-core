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

set ddc_file [file normalize [required_env HDEC_DDC]]
set saif_file [file normalize [required_env HDEC_SAIF]]
set out_dir [file normalize [required_env HDEC_POWER_OUT]]
set instance_name [optional_env HDEC_SAIF_INSTANCE tb_vv35_schedule_gate/dut]
file mkdir $out_dir

set target_libs [required_env HDEC_TARGET_LIBS]
set link_libs [optional_env HDEC_LINK_LIBS $target_libs]
set search_dirs {}
foreach lib [concat $target_libs $link_libs] {
    lappend search_dirs [file dirname [file normalize $lib]]
}
set_app_var search_path [concat $search_path $search_dirs]
set_app_var target_library $target_libs
set_app_var link_library [concat "*" $target_libs $link_libs]

read_ddc $ddc_file
current_design hdec_top
if {![link]} {
    error "Link failed for hdec_top power analysis"
}
catch {reset_switching_activity}

set read_status [catch {
    read_saif -input $saif_file -instance_name $instance_name -verbose
} read_message]
set read_log [open [file join $out_dir read_saif_status.txt] w]
puts $read_log "status=$read_status"
puts $read_log "instance_name=$instance_name"
puts $read_log "message=$read_message"
close $read_log
if {$read_status != 0} {
    error "read_saif failed: $read_message"
}

update_power
redirect -file [file join $out_dir power.rpt] {report_power -verbose}
if {[catch {
    redirect -file [file join $out_dir power_hierarchy.rpt] {
        report_power -hierarchy -levels 6 -verbose
    }
} hierarchy_error]} {
    redirect -file [file join $out_dir power_hierarchy.rpt] {
        report_power -hierarchy
    }
    set hierarchy_note [open [file join $out_dir power_hierarchy_fallback.txt] w]
    puts $hierarchy_note $hierarchy_error
    close $hierarchy_note
}
redirect -file [file join $out_dir timing.rpt] {report_timing -delay_type max -max_paths 50}
redirect -file [file join $out_dir area.rpt] {report_area -hierarchy}

set saif_audit [open [file join $out_dir saif_annotation_audit.rpt] w]
if {[catch {redirect -variable report_text {report_saif -hierarchy}} report_error]} {
    puts $saif_audit "optional_report_saif=UNAVAILABLE message=$report_error"
} else {
    puts $saif_audit "optional_report_saif=PASS"
    puts $saif_audit $report_text
}
if {[catch {redirect -variable missing_text {report_switching_activity -list_not_annotated}} missing_error]} {
    puts $saif_audit "audit_status=FAIL message=$missing_error"
} else {
    puts $saif_audit "audit_status=PASS"
    puts $saif_audit $missing_text
}
close $saif_audit

set context [open [file join $out_dir power_context.txt] w]
puts $context "ddc=$ddc_file"
puts $context "saif=$saif_file"
puts $context "saif_instance=$instance_name"
puts $context "scenario=[optional_env HDEC_SCENARIO NOT_SET]"
puts $context "vrf_mode=[optional_env HDEC_VRF_MODE NOT_SET]"
set vrf_mode [string toupper [optional_env HDEC_VRF_MODE NOT_SET]]
if {$vrf_mode eq "REG_VRF"} {
    puts $context "qualification=PRE_LAYOUT_COMPLETE_REGISTER_VRF"
} elseif {$vrf_mode eq "SRAM_MACRO_VRF"} {
    puts $context "qualification=PRE_LAYOUT_COMPLETE_SRAM_MACRO_VRF"
} else {
    puts $context "qualification=PRE_LAYOUT_LOGIC_CORE_EXCLUDING_VRF_SRAM"
}
puts $context "saif_coverage_requires_review=true"
close $context

quit
