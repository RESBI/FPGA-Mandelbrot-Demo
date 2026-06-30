set bit_file [lindex $argv 0]
if {$bit_file == ""} {
    # Auto-detect: try the common build outputs first.
    set bit_files [glob -nocomplain "./fp64_proj/mandelbrot_fp64.runs/impl_1/*.bit"]
    if {[llength $bit_files] == 0} {
        set bit_files [glob -nocomplain "./fp64_dynamic_proj/mandelbrot_fp64_dynamic.runs/impl_1/*.bit"]
    }
    if {[llength $bit_files] == 0} {
        set bit_files [glob -nocomplain "./uart_echo_proj/uart_echo.runs/impl_1/*.bit"]
    }
    if {[llength $bit_files] == 0} {
        set bit_files [glob -nocomplain "./uart_tx_pattern_proj/uart_tx_pattern.runs/impl_1/*.bit"]
    }
    if {[llength $bit_files] == 0} {
        set bit_files [glob -nocomplain "./fp128_proj/mandelbrot_fp128.runs/impl_1/*.bit"]
    }
    if {[llength $bit_files] > 0} {
        set bit_file [lindex $bit_files 0]
    } else {
        puts "ERROR: No bitstream found. Build first."
        exit 1
    }
}

puts "========================================"
puts " Programming FPGA"
puts " Bitstream: $bit_file"
puts "========================================"

open_hw_manager
connect_hw_server

set hw_targets [get_hw_targets]
if {[llength $hw_targets] == 0} {
    puts "ERROR: No hardware targets found"
    close_hw_manager
    exit 1
}

open_hw_target
set hw_devices [get_hw_devices]
if {[llength $hw_devices] == 0} {
    puts "ERROR: No hardware devices found"
    close_hw_manager
    exit 1
}

puts "Found [llength $hw_devices] device(s)"
set hw_device ""
foreach dev $hw_devices {
    if {[string match "*xczu4*" $dev] || [string match "*xc7k70t*" $dev]} {
        set hw_device $dev
        break
    }
}
if {$hw_device == ""} {
    puts "ERROR: No supported FPGA device found"
    puts "Available: $hw_devices"
    close_hw_manager
    exit 1
}
puts "Target device: $hw_device"

refresh_hw_device -update_hw_probes false $hw_device
set_property PROBES.FILE {} $hw_device
set_property FULL_PROBES.FILE {} $hw_device
set_property PROGRAM.FILE $bit_file $hw_device

puts "Programming..."
program_hw_devices $hw_device
puts "Programming complete"

close_hw_manager
puts "Done"
