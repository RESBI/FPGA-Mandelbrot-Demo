# active high
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D25} [get_ports {LED[3]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C21} [get_ports {LED[4]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D26} [get_ports {LED[5]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C26} [get_ports {LED[6]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN F25} [get_ports {LED[7]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN G25} [get_ports {LED[8]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E25} [get_ports {LED[9]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E26} [get_ports {LED[10]}]
# active low
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E18} [get_ports J1_GREEN]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E17} [get_ports J1_RED]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E16} [get_ports J2_GREEN]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E15} [get_ports J2_RED]
