set part_name "xc7k70tfbg676-1"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc"

set worker_contexts 4
foreach arg $argv {
    if {[string is integer -strict $arg]} {
        set worker_contexts $arg
    } elseif {[string match "WORKER_CONTEXTS=*" $arg]} {
        set worker_contexts [string range $arg [string length "WORKER_CONTEXTS="] end]
    }
}

set proj_name "mandelbrot_fp64_ctx${worker_contexts}"
set proj_dir  "./fp64_ctx${worker_contexts}_proj"

puts "========================================"
puts " Mandelbrot FP64 Context Build Script"
puts " Part: $part_name"
puts " Scheduler: dynamic idle-core rows (SCHED_MODE=1)"
puts " Worker pipeline contexts: $worker_contexts"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
set_property top top [current_fileset]
set_property generic "SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096 WORKER_CONTEXTS=$worker_contexts" [current_fileset]
puts "Added [llength [glob $rtl_dir/*.v]] source files"

set_property include_dirs $rtl_dir [current_fileset]

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
