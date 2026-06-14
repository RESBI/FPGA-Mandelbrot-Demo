set part_name "xc7z010clg400-1"
set proj_name "uart_echo"
set proj_dir  "./uart_echo_proj"
set rtl_dir   "./rtl"
set xdc_dir   "./constraints"

puts "========================================"
puts " UART Echo Build Script"
puts " Part: $part_name"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list \
    $rtl_dir/uart_rx.v \
    $rtl_dir/uart_tx.v \
    $rtl_dir/uart_echo_top.v \
]
set_property top uart_echo_top [current_fileset]
set_property include_dirs $rtl_dir [current_fileset]

add_files -fileset constrs_1 [glob $xdc_dir/*.xdc]

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
