set part_name "xczu4ev-sfvc784-2-i"
set proj_name "mandelbrot_with_ram"
set proj_dir  "./mandelbrot_with_ram_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_vmc_rtsb_zu4ev/mandelbrot_with_ram.xdc"
set ref_bd_file "./reference/design_1.bd"
set pl_clk_hz "200000000"

proc set_ps_property_if_exists {cell prop value} {
    if {[lsearch -exact [list_property $cell] $prop] >= 0} {
        set_property $prop $value $cell
    }
}

proc apply_ps_config_from_bd {cell bd_file} {
    if {![file exists $bd_file]} { puts "WARNING: Reference BD not found: $bd_file"; return }
    set fd [open $bd_file r]
    set bd_text [read $fd]
    close $fd
    set ps_props [list]
    set matches [regexp -all -inline {"([A-Za-z0-9_]+)"[ \t\r\n]*:[ \t\r\n]*\{[ \t\r\n]*"value"[ \t\r\n]*:[ \t\r\n]*"([^"]*)"[ \t\r\n]*\}} $bd_text]
    foreach {full key value} $matches {
        if {[regexp {ACT_FREQ|HIGHADDR|LOWADDR|FREQMHZ$} $key]} { continue }
        set prop CONFIG.$key
        if {[lsearch -exact [list_property $cell] $prop] >= 0} { lappend ps_props $prop $value }
    }
    if {[llength $ps_props]} {
        if {[catch {set_property -dict $ps_props $cell} err]} { puts "ERROR: $err"; exit 1 }
    }
    puts "Applied [expr {[llength $ps_props] / 2}] PS properties from reference BD"
}

proc enable_ps_ddr_high_address {cell} {
    set high_addr_props [list]
    foreach {prop value} {
        CONFIG.PSU__DDRC__DEVICE_CAPACITY {8192 MBits}
        CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits}
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT 16
        CONFIG.PSU_DDR_RAM_HIGHADDR 0xFFFFFFFF
        CONFIG.PSU_DDR_RAM_LOWADDR_OFFSET 0x80000000
        CONFIG.PSU_DDR_RAM_HIGHADDR_OFFSET 0x800000000
        CONFIG.PSU__HIGH_ADDRESS__ENABLE 1
        CONFIG.PSU__DDR_HIGH_ADDRESS_GUI_ENABLE 1
    } {
        if {[lsearch -exact [list_property $cell] $prop] >= 0} { lappend high_addr_props $prop $value }
    }
    if {[llength $high_addr_props]} { set_property -dict $high_addr_props $cell }
    set prop CONFIG.PSU__PROTECTION__SLAVES
    if {[lsearch -exact [list_property $cell] $prop] < 0} { puts "ERROR: $prop not found"; exit 1 }
    set slaves [get_property $prop $cell]
    set high_pattern {DDR;DDR_HIGH;800000000;[0-9A-Fa-f]+;[01]}
    if {![regexp $high_pattern $slaves high_token]} { puts "ERROR: DDR_HIGH not found"; exit 1 }
    regsub {;[01]$} $high_token {;1} enabled_token
    if {$high_token ne $enabled_token} {
        regsub $high_pattern $slaves $enabled_token slaves
        set_property $prop $slaves $cell
    }
    puts "Enabled DDR_HIGH protection slave"
}

proc connect_bd_pin_if_exists {src dst} {
    set src_pin [get_bd_pins -quiet $src]
    if {![llength $src_pin]} { set src_pin [get_bd_ports -quiet $src] }
    set dst_pin [get_bd_pins -quiet $dst]
    if {![llength $dst_pin]} { set dst_pin [get_bd_ports -quiet $dst] }
    if {[llength $src_pin] && [llength $dst_pin]} { connect_bd_net $src_pin $dst_pin; return 1 }
    return 0
}

puts "========================================"
puts " Mandelbrot PL-PS DDR Build"
puts " Part: $part_name"
puts " PL clock: ${pl_clk_hz} Hz on E12"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sources_1 [glob $rtl_dir/*.vh]
set_property include_dirs $rtl_dir [current_fileset]
add_files -fileset constrs_1 $xdc_file

create_bd_design "system"

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0
set ps [get_bd_cells zynq_ultra_ps_e_0]
apply_ps_config_from_bd $ps $ref_bd_file
enable_ps_ddr_high_address $ps
set_ps_property_if_exists $ps CONFIG.PSU__FPGA_PL0_ENABLE 1
set_ps_property_if_exists $ps CONFIG.PSU__USE__FABRIC__RST 1
set_ps_property_if_exists $ps CONFIG.PSU__USE__S_AXI_GP0 1
set_ps_property_if_exists $ps CONFIG.PSU__SAXIGP0__DATA_WIDTH 64

create_bd_cell -type module -reference top_with_ram mandelbrot_0
set_property -dict [list \
    CONFIG.CLK_HZ $pl_clk_hz \
    CONFIG.UART_BAUD 12000000 \
    CONFIG.CORE_COUNT 22 \
    CONFIG.FX_CONTEXTS 4 \
    CONFIG.WORKER_CONTEXTS 4 \
    CONFIG.WORKER_MODE 1 \
    CONFIG.SCHED_MODE 1 \
] [get_bd_cells mandelbrot_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_smc_0
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells axi_smc_0]

create_bd_cell -type module -reference pl_por pl_por_0
set_property -dict [list CONFIG.CLK_HZ $pl_clk_hz CONFIG.RST_MS 5 CONFIG.USE_EXT_RST 0] [get_bd_cells pl_por_0]

create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ $pl_clk_hz [get_bd_ports sys_clk]

connect_bd_net [get_bd_ports sys_clk] [get_bd_pins mandelbrot_0/aclk]
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins axi_smc_0/aclk]
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins pl_por_0/clk]
connect_bd_net -quiet [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins pl_por_0/ext_rstn]
connect_bd_net [get_bd_pins pl_por_0/rstn] [get_bd_pins mandelbrot_0/aresetn]
connect_bd_net [get_bd_pins pl_por_0/rstn] [get_bd_pins axi_smc_0/aresetn]

foreach pin_name {saxihp0_fpd_aclk saxigp0_aclk saxihpc0_fpd_aclk maxihpm0_lpd_aclk maxihpm0_fpd_aclk} {
    if {[connect_bd_pin_if_exists sys_clk zynq_ultra_ps_e_0/$pin_name]} { puts "Connected $pin_name" }
}

set axi_connected 0
foreach ps_intf {S_AXI_HPC0_FPD S_AXI_HP0_FPD S_AXI_HP0} {
    if {[llength [get_bd_intf_pins -quiet axi_smc_0/M00_AXI]] && [llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/$ps_intf]]} {
        connect_bd_intf_net [get_bd_intf_pins mandelbrot_0/M_AXI] [get_bd_intf_pins axi_smc_0/S00_AXI]
        connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/$ps_intf]
        set axi_connected 1
        puts "Connected mandelbrot_0/M_AXI through axi_smc_0 to zynq_ultra_ps_e_0/$ps_intf"
        break
    }
}
if {$axi_connected == 0} { puts "ERROR: No PS HP interface found"; exit 1 }

make_bd_pins_external [get_bd_pins mandelbrot_0/uart_rx]
make_bd_pins_external [get_bd_pins mandelbrot_0/uart_tx]
set_property name uart_rx [get_bd_ports uart_rx_0]
set_property name uart_tx [get_bd_ports uart_tx_0]

if {[llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/DDR]]} {
    make_bd_intf_pins_external [get_bd_intf_pins zynq_ultra_ps_e_0/DDR]
}
if {[llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/FIXED_IO]]} {
    make_bd_intf_pins_external [get_bd_intf_pins zynq_ultra_ps_e_0/FIXED_IO]
}

assign_bd_address

set has_ddr_high 0
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces mandelbrot_0/M_AXI]] {
    puts "  $seg offset=[get_property OFFSET $seg] range=[get_property RANGE $seg]"
    if {[string first "DDR_HIGH" $seg] >= 0} { set has_ddr_high 1 }
}
if {$has_ddr_high == 0} { puts "ERROR: DDR_HIGH not assigned"; exit 1 }

validate_bd_design
save_bd_design
set_property synth_checkpoint_mode None [get_files $proj_dir/$proj_name.srcs/sources_1/bd/system/system.bd]

make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "--- Running Synthesis ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: Synthesis failed"; exit 1 }

puts "--- Running Implementation + Bitstream ---"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: Implementation failed"; exit 1 }

open_run impl_1
report_timing_summary -file $proj_dir/$proj_name.runs/impl_1/top_timing_summary_routed.rpt
report_utilization -file $proj_dir/$proj_name.runs/impl_1/top_utilization_routed.rpt

set bit_files [glob -nocomplain $proj_dir/$proj_name.runs/impl_1/*.bit]
if {[llength $bit_files] > 0} {
    puts "BUILD SUCCESSFUL"
    puts "Bitstream: [lindex $bit_files 0]"
} else {
    puts "ERROR: Bitstream not found"; exit 1
}

set xsa_file "./mandelbrot_with_ram.xsa"
if {[catch {write_hw_platform -fixed -include_bit -force $xsa_file} err]} {
    puts "WARNING: write_hw_platform failed: $err"
}
if {[file exists $xsa_file]} { puts "XSA exported: [file normalize $xsa_file]" }
