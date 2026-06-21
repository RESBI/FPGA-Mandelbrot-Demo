# Mandelbrot XC7K70T board-level constraints.
# FT232HL TX -> FPGA RX on J23, FT232HL RX <- FPGA TX on H24.

create_clock -name clk_200 -period 5.000 [get_ports CLK_200_P]

set_property PACKAGE_PIN AA10 [get_ports CLK_200_P]
set_property PACKAGE_PIN AB10 [get_ports CLK_200_N]
set_property IOSTANDARD LVDS [get_ports {CLK_200_P CLK_200_N}]

set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN J23 } [get_ports uart_rx]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN H24 } [get_ports uart_tx]

# Active-high board debug LEDs, using natural board numbering.
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D25 } [get_ports {LED[3]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C21 } [get_ports {LED[4]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D26 } [get_ports {LED[5]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C26 } [get_ports {LED[6]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN F25 } [get_ports {LED[7]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN G25 } [get_ports {LED[8]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E25 } [get_ports {LED[9]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E26 } [get_ports {LED[10]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN J26 } [get_ports {LED[11]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN J25 } [get_ports {LED[12]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN H26 } [get_ports {LED[13]}]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN G26 } [get_ports {LED[14]}]

# J1 bi-color LED is active-low and reserved for UART activity: green=RX, red=TX.
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E18 } [get_ports J1_GREEN]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E17 } [get_ports J1_RED]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
