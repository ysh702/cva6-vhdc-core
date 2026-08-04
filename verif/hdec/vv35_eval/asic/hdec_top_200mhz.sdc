# VV35 standalone hdec_top synthesis constraint template.
# All values below are reported in the run manifest and may be overridden by
# environment variables before this file is sourced by dc_synth.tcl.

proc hdec_env_or {name default_value} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default_value
}

set hdec_period_ns [hdec_env_or HDEC_PERIOD_NS 5.000]
set hdec_uncertainty_ns [hdec_env_or HDEC_CLOCK_UNCERTAINTY_NS 0.100]
set hdec_input_delay_ns [hdec_env_or HDEC_INPUT_DELAY_NS 0.500]
set hdec_output_delay_ns [hdec_env_or HDEC_OUTPUT_DELAY_NS 0.500]
set hdec_input_transition_ns [hdec_env_or HDEC_INPUT_TRANSITION_NS 0.100]
set hdec_output_load [hdec_env_or HDEC_OUTPUT_LOAD 0.010]
set hdec_max_transition_ns [hdec_env_or HDEC_MAX_TRANSITION_NS 0.500]
set hdec_max_fanout [hdec_env_or HDEC_MAX_FANOUT 32]

create_clock -name clk_i -period $hdec_period_ns [get_ports clk_i]
set_clock_uncertainty $hdec_uncertainty_ns [get_clocks clk_i]

set hdec_data_inputs [remove_from_collection [all_inputs] [get_ports {clk_i rst_ni}]]
if {[sizeof_collection $hdec_data_inputs] > 0} {
    set_input_delay $hdec_input_delay_ns -clock clk_i $hdec_data_inputs
    set_input_transition $hdec_input_transition_ns $hdec_data_inputs
}
if {[sizeof_collection [all_outputs]] > 0} {
    set_output_delay $hdec_output_delay_ns -clock clk_i [all_outputs]
    set_load $hdec_output_load [all_outputs]
}

set_false_path -from [get_ports rst_ni]
set_max_transition $hdec_max_transition_ns [current_design]
set_max_fanout $hdec_max_fanout [current_design]

puts "HDEC_SDC period_ns=$hdec_period_ns uncertainty_ns=$hdec_uncertainty_ns input_delay_ns=$hdec_input_delay_ns output_delay_ns=$hdec_output_delay_ns input_transition_ns=$hdec_input_transition_ns output_load_library_units=$hdec_output_load max_transition_ns=$hdec_max_transition_ns max_fanout=$hdec_max_fanout"
