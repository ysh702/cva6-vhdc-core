set_property PACKAGE_PIN U18 [get_ports L16]
set_property IOSTANDARD LVCMOS33 [get_ports L16]
create_clock -name clk50 -period 20.000 [get_ports L16]

set_property PACKAGE_PIN N16 [get_ports KEY]
set_property IOSTANDARD LVCMOS33 [get_ports KEY]
set_property PULLUP true [get_ports KEY]

set_property PACKAGE_PIN H15 [get_ports LED_H15]
set_property IOSTANDARD LVCMOS33 [get_ports LED_H15]
