set part_name "xc7k70tfbg676-1"
set proj_name "mandelbrot_fp128"
set proj_dir  "./fp128_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_hvs_xc7k70t/mandelbrot_top.xdc"

puts "========================================"
puts " Mandelbrot FP128 Build Script"
puts " Part: $part_name"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

# Add all RTL files
add_files -fileset sources_1 [glob $rtl_dir/*.v]
set_property top top [current_fileset]
puts "Added [llength [glob $rtl_dir/*.v]] source files"

# Set Verilog include path and define FP128
set_property include_dirs $rtl_dir [current_fileset]
set_property verilog_define {FP128_MODE} [current_fileset]

add_files -fileset constrs_1 $xdc_file
puts "Added constraint files"

puts ""
puts "--- Running Synthesis ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}
puts "Synthesis complete"

puts ""
puts "--- Running Implementation + Bitstream ---"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}
puts "Implementation complete"

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
