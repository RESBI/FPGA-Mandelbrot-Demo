set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
set_property -dict { PACKAGE_PIN U20   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];
set_property -dict { PACKAGE_PIN V20   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

create_clock -period 10.000 -name sys_clk [get_ports sys_clk];

# True 100 MHz core experiment: FP_CE_DIV=1, so no multicycle exceptions.
