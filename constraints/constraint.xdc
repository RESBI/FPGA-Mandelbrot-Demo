set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
set_property -dict { PACKAGE_PIN U20   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];
set_property -dict { PACKAGE_PIN V20   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

create_clock -period 10.000 -name sys_clk [get_ports sys_clk];

# mandelbrot_core and FP units advance only when top.fp_ce is asserted.
# FP64 uses FP_CE_DIV=2, so CE-gated datapath registers have two sys_clk
# cycles between meaningful launches and captures while UART stays at 100 MHz.
set fp_ce_regs [get_cells -hier -filter {NAME =~ *u_core/* && IS_SEQUENTIAL}]
set_multicycle_path 2 -setup -from $fp_ce_regs -to $fp_ce_regs
set_multicycle_path 1 -hold  -from $fp_ce_regs -to $fp_ce_regs
