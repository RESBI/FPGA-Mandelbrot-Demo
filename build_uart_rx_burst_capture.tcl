set part_name "xczu4ev-sfvc784-1-i"
set proj_name "uart_rx_burst_capture"
set proj_dir  "./uart_rx_burst_capture_zu4ev_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_vmc_rtsb_zu4ev/led.xdc"

puts "========================================"
puts " UART RX Burst Capture Build Script"
puts " Part: $part_name"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list \
    $rtl_dir/uart_rx.v \
    $rtl_dir/uart_tx.v \
    $rtl_dir/uart_rx_burst_capture_top.v \
]
set_property top uart_rx_burst_capture_top [current_fileset]
set_property include_dirs $rtl_dir [current_fileset]

add_files -fileset constrs_1 $xdc_file

puts ""
puts "--- Running Synthesis ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

puts ""
puts "--- Running Implementation + Bitstream ---"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

set bit_files [glob -nocomplain $proj_dir/$proj_name.runs/impl_1/*.bit]
if {[llength $bit_files] > 0} {
    puts ""
    puts "========================================"
    puts " BUILD SUCCESSFUL"
    puts " Bitstream: [lindex $bit_files 0]"
    puts "========================================"
} else {
    puts "ERROR: Bitstream not found"
    exit 1
}
