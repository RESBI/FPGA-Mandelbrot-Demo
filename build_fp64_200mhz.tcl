set part_name "xc7k70tfbg676-1"
set worker_contexts 4

if {$argc >= 1} {
    set worker_contexts [lindex $argv 0]
}

set proj_name "mandelbrot_fp64_200mhz_ctx${worker_contexts}"
set proj_dir  "./fp64_200mhz_ctx${worker_contexts}_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_hvs_xc7k70t/mandelbrot_top.xdc"

puts "========================================"
puts " Mandelbrot FP64 200 MHz Experiment"
puts " Part: $part_name"
puts " Clocking: direct 200 MHz BUFG"
puts " Scheduler: dynamic idle-core rows (SCHED_MODE=1)"
puts " Worker pipeline contexts: $worker_contexts"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
set_property top top [current_fileset]
set_property generic "CLK_HZ=200000000 DIRECT_200MHZ=1 SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096 WORKER_CONTEXTS=$worker_contexts" [current_fileset]
puts "Added [llength [glob $rtl_dir/*.v]] source files"

set_property include_dirs $rtl_dir [current_fileset]

add_files -fileset constrs_1 $xdc_file
puts "Added constraint files"

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STRATEGY Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

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

open_run impl_1
report_timing_summary -file $proj_dir/${proj_name}.runs/impl_1/top_timing_summary_routed.rpt
report_timing -max_paths 25 -sort_by group -file $proj_dir/${proj_name}.runs/impl_1/top_timing_paths_routed.rpt
report_utilization -file $proj_dir/${proj_name}.runs/impl_1/top_utilization_routed.rpt

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
