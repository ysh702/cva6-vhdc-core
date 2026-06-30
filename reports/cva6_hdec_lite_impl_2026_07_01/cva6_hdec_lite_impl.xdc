create_clock -period 5.000 -name sys_clk [get_ports clk_pad_i]
set_clock_uncertainty 0.100 [get_clocks sys_clk]

set_false_path -from [get_ports rst_ni]
set_output_delay -clock [get_clocks sys_clk] 0.000 [get_ports keep_o[*]]

set_property IOSTANDARD LVCMOS33 [get_ports {clk_pad_i rst_ni keep_o[*]}]
