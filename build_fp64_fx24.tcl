set part_name "xczu4ev-sfvc784-1-i"
set proj_name "mandelbrot_fp64_fx24"
set proj_dir  "./fp64_fx24_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc"

puts "========================================"
puts " Mandelbrot FP64 Fixed-Point Build"
puts " Workers: 24, Contexts: 4, Mode: fx"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
set_property top top [current_fileset]
set_property generic {CLK_HZ=200000000 DIRECT_200MHZ=1 SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096 CORE_COUNT=24 WORKER_MODE=1 FX_CONTEXTS=4 WORKER_CONTEXTS=4 RESPONSE_TILE_ROW_SPLITS=8} [current_fileset]

set_property include_dirs $rtl_dir [current_fileset]
add_files -fileset constrs_1 $xdc_file

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STRATEGY Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: Synthesis failed"; exit 1 }
puts "Synthesis complete"

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
