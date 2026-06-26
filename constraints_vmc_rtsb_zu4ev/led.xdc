############## clock define##################
create_clock -name sys_clk -period 40.690 [get_ports sys_clk]
set_property PACKAGE_PIN E10 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS25 [get_ports sys_clk]
############## key define##################
set_property PACKAGE_PIN D14 [get_ports rst_n]
set_property IOSTANDARD LVCMOS25 [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]
##############LED define##################
# LED0/LED1 pins are occupied by FT232HL UART on this board revision.

############## FT232HL UART define##################
# FT232HL TX -> FPGA RX uses LED1 pin; FT232HL RX <- FPGA TX uses LED0 pin.
set_property PACKAGE_PIN D12 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS25 [get_ports uart_rx]

set_property PACKAGE_PIN C12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS25 [get_ports uart_tx]

set_property PACKAGE_PIN A11 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[2]}]

set_property PACKAGE_PIN A12 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[3]}]

#set_property PACKAGE_PIN G1 [get_ports {led[4]}]
#set_property IOSTANDARD LVCMOS25 [get_ports {led[4]}]

#set_property PACKAGE_PIN E3 [get_ports {led[5]}]
#set_property IOSTANDARD LVCMOS25 [get_ports {led[5]}]

#set_property PACKAGE_PIN G3 [get_ports {led[6]}]
#set_property IOSTANDARD LVCMOS25 [get_ports {led[6]}]

#set_property PACKAGE_PIN H3 [get_ports {led[7]}]
#set_property IOSTANDARD LVCMOS25 [get_ports {led[7]}]

