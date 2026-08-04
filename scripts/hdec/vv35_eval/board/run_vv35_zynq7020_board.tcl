if {$argc != 3 && $argc != 4} {
    error "Expected: <bitstream_path> <ltx_path> <results_csv> ?trial_count?"
}

set bitstream_path [file normalize [lindex $argv 0]]
set ltx_path       [file normalize [lindex $argv 1]]
set results_csv    [file normalize [lindex $argv 2]]
set trial_count    1
if {$argc == 4} {
    set trial_count [lindex $argv 3]
    if {![string is integer -strict $trial_count] || $trial_count < 1} {
        error "trial_count must be a positive integer, got '$trial_count'"
    }
}
foreach path [list $bitstream_path $ltx_path] {
    if {![file exists $path]} { error "Required hardware file not found: $path" }
}

proc find_vio_probe {vio name} {
    # Hardware Manager names probes after their connected RTL nets, not after
    # the VIO port names stored in the LTX file.
    set matches [get_hw_probes -quiet $name -of_objects $vio]
    if {[llength $matches] != 1} {
        error "Expected one VIO probe named $name, got '$matches'"
    }
    return [lindex $matches 0]
}

proc probe_value {probe} {
    foreach prop {INPUT_VALUE VALUE} {
        if {![catch {set value [get_property $prop $probe]}]} { return $value }
    }
    return "UNREADABLE"
}

proc hex_uint {raw label} {
    if {![regexp {^[0-9A-Fa-f]+$} $raw]} {
        error "$label is not a hexadecimal VIO value: '$raw'"
    }
    return [expr "0x$raw"]
}

proc require_equal {scenario field actual expected} {
    if {$actual != $expected} {
        error "$scenario $field mismatch: got $actual, expected $expected"
    }
}

open_hw_manager
catch {close_hw_target}
catch {disconnect_hw_server}
connect_hw_server -allow_non_jtag
set targets [get_hw_targets -quiet]
if {[llength $targets] != 1} {
    error "Expected exactly one hardware target, got '$targets'"
}
set target [lindex $targets 0]
current_hw_target $target
if {[catch {open_hw_target} open_error]} {
    error "Could not open hardware target $target: $open_error"
}

set devs [get_hw_devices xc7z020*]
if {[llength $devs] != 1} { error "Expected one xc7z020 hardware device, got '$devs'" }
set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bitstream_path $dev
set_property PROBES.FILE $ltx_path $dev
program_hw_devices $dev
refresh_hw_device $dev

set vios [get_hw_vios -quiet]
if {[llength $vios] != 1} { error "Expected one VIO core, got '$vios'" }
set vio [lindex $vios 0]
set p_arm               [find_vio_probe $vio vio_arm_toggle]
set p_mode              [find_vio_probe $vio vio_mode]
set p_pass              [find_vio_probe $vio snapshot_pass_q]
set p_fail              [find_vio_probe $vio snapshot_fail_q]
set p_valid             [find_vio_probe $vio snapshot_valid_q_reg_n_0]
set p_idle              [find_vio_probe $vio idle]
set p_busy              [find_vio_probe $vio busy]
set p_metric            [find_vio_probe $vio metric_active]
set p_actual_mode       [find_vio_probe $vio snapshot_mode_q]
set p_phase             [find_vio_probe $vio phase]
set p_cycles            [find_vio_probe $vio snapshot_cycles_q]
set p_hmatch            [find_vio_probe $vio snapshot_hmatch_q]
set p_errors            [find_vio_probe $vio snapshot_errors_q]
set p_error_code        [find_vio_probe $vio snapshot_error_code_q]
set p_last_hmatch       [find_vio_probe $vio snapshot_last_hmatch_q]
set p_final_status      [find_vio_probe $vio snapshot_final_status_q]
set p_preload           [find_vio_probe $vio snapshot_preload_q]
set p_sequence          [find_vio_probe $vio snapshot_sequence_q]
set p_hmatch_completion [find_vio_probe $vio snapshot_hmatch_completion_cycles_q]

set fh [open $results_csv w]
puts $fh "trial,scenario,requested_mode,actual_mode,sequence,snapshot_valid,pass,fail,idle,busy,metric_active,phase,window_cycles,hmatch_completed,error_count,error_code,last_hmatch,final_status,preload_count,hmatch_completion_cycles,validation"

# Change arm exactly once per run, then keep JTAG quiet until completion so
# debug traffic does not enter the physical measurement window.
set arm_value 0
set expected_sequence 0
for {set trial 1} {$trial <= $trial_count} {incr trial} {
  foreach scenario_spec {{INTERLEAVED 1 250} {SERIAL 0 250} {CLOCKED_IDLE 2 250}} {
    lassign $scenario_spec scenario mode wait_ms
    set arm_value [expr {!$arm_value}]
    set_property OUTPUT_VALUE $mode $p_mode
    set_property OUTPUT_VALUE $arm_value $p_arm
    commit_hw_vio [list $p_mode $p_arm]
    after $wait_ms
    refresh_hw_vio $vio

    set actual_mode_raw       [probe_value $p_actual_mode]
    set sequence_raw          [probe_value $p_sequence]
    set valid_raw             [probe_value $p_valid]
    set pass_raw              [probe_value $p_pass]
    set fail_raw              [probe_value $p_fail]
    set idle_raw              [probe_value $p_idle]
    set busy_raw              [probe_value $p_busy]
    set metric_raw            [probe_value $p_metric]
    set phase_raw             [probe_value $p_phase]
    set cycles_raw            [probe_value $p_cycles]
    set hmatch_raw            [probe_value $p_hmatch]
    set errors_raw            [probe_value $p_errors]
    set error_code_raw        [probe_value $p_error_code]
    set last_hmatch_raw       [probe_value $p_last_hmatch]
    set final_status_raw      [probe_value $p_final_status]
    set preload_raw           [probe_value $p_preload]
    set hmatch_completion_raw [probe_value $p_hmatch_completion]

    set actual_mode       [hex_uint $actual_mode_raw actual_mode]
    set sequence          [hex_uint $sequence_raw sequence]
    set valid             [hex_uint $valid_raw snapshot_valid]
    set pass_value        [hex_uint $pass_raw pass]
    set fail_value        [hex_uint $fail_raw fail]
    set idle_value        [hex_uint $idle_raw idle]
    set busy_value        [hex_uint $busy_raw busy]
    set metric_value      [hex_uint $metric_raw metric_active]
    set phase_value       [hex_uint $phase_raw phase]
    set cycles            [hex_uint $cycles_raw window_cycles]
    set hmatch            [hex_uint $hmatch_raw hmatch_completed]
    set errors            [hex_uint $errors_raw error_count]
    set error_code        [hex_uint $error_code_raw error_code]
    set last_hmatch       [hex_uint $last_hmatch_raw last_hmatch]
    set final_status      [hex_uint $final_status_raw final_status]
    set preload           [hex_uint $preload_raw preload_count]
    set hmatch_completion [hex_uint $hmatch_completion_raw hmatch_completion_cycles]

    incr expected_sequence
    require_equal $scenario actual_mode $actual_mode $mode
    require_equal $scenario sequence $sequence $expected_sequence
    require_equal $scenario snapshot_valid $valid 1
    require_equal $scenario pass $pass_value 1
    require_equal $scenario fail $fail_value 0
    require_equal $scenario idle $idle_value 1
    require_equal $scenario busy $busy_value 0
    require_equal $scenario metric_active $metric_value 0
    require_equal $scenario phase $phase_value 0
    require_equal $scenario error_count $errors 0
    require_equal $scenario error_code $error_code 0
    require_equal $scenario preload_count $preload 112

    switch -- $scenario {
        INTERLEAVED {
            set expected_cycles 200144
            set expected_hmatch 1632
            set expected_completion 200114
            set expected_last_hmatch 0x1f9
            set expected_final_status 0x48
        }
        SERIAL {
            set expected_cycles 337853
            set expected_hmatch 1632
            set expected_completion 337853
            set expected_last_hmatch 0x1f9
            set expected_final_status 0x48
        }
        CLOCKED_IDLE {
            set expected_cycles 2000000
            set expected_hmatch 0
            set expected_completion 0
            set expected_last_hmatch 0
            set expected_final_status 0
        }
        default { error "Unknown board scenario $scenario" }
    }
    require_equal $scenario window_cycles $cycles $expected_cycles
    require_equal $scenario hmatch_completed $hmatch $expected_hmatch
    require_equal $scenario hmatch_completion_cycles $hmatch_completion $expected_completion
    require_equal $scenario last_hmatch $last_hmatch $expected_last_hmatch
    require_equal $scenario final_status $final_status $expected_final_status

    set row [list $trial $scenario $mode \
        $actual_mode_raw $sequence_raw $valid_raw $pass_raw $fail_raw \
        $idle_raw $busy_raw $metric_raw $phase_raw $cycles_raw \
        $hmatch_raw $errors_raw $error_code_raw $last_hmatch_raw \
        $final_status_raw $preload_raw $hmatch_completion_raw PASS]
    puts $fh [join $row ,]
    puts "VV35_BOARD_RESULT=[join $row ,]"
  }
}
close $fh

if {![catch {set sysmons [get_hw_sysmons -quiet]}]} {
    foreach sysmon $sysmons {
        catch {refresh_hw_sysmon $sysmon}
        foreach prop {TEMPERATURE VCCINT VCCAUX VCCBRAM} {
            if {![catch {set value [get_property $prop $sysmon]}]} {
                puts "VV35_SYSMON=$prop,$value"
            }
        }
    }
}
puts "VV35_BOARD_RESULTS_CSV=$results_csv"
