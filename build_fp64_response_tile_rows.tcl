set part_name "xczu4ev-sfvc784-1-i"
set rtl_dir   "./rtl"
set xdc_file  "./constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc"

set RESPONSE_TILE_ROW_SPLITS 8
if {[llength $argv] >= 1} {
    set RESPONSE_TILE_ROW_SPLITS [lindex $argv 0]
}

set proj_name "mandelbrot_fp64_rtr${RESPONSE_TILE_ROW_SPLITS}"
set proj_dir  "./fp64_rtr${RESPONSE_TILE_ROW_SPLITS}_proj"

puts "========================================"
puts " Mandelbrot FP64 response-row-tile sweep build"
puts " Part: $part_name"
puts " Workers/contexts: 12/8"
puts " RESPONSE_TILE_ROW_SPLITS: $RESPONSE_TILE_ROW_SPLITS"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
set_property top top [current_fileset]
set_property generic "CLK_HZ=200000000 DIRECT_200MHZ=1 SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096 CORE_COUNT=12 WORKER_CONTEXTS=8 WORKER_ADD_UNITS=1 WORKER_MUL_UNITS=1 RESPONSE_TILE_ROW_SPLITS=$RESPONSE_TILE_ROW_SPLITS" [current_fileset]
puts "Added [llength [glob $rtl_dir/*.v]] source files"

set_property include_dirs $rtl_dir [current_fileset]
add_files -fileset constrs_1 $xdc_file

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STRATEGY Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

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

open_run impl_1
report_timing_summary -file $proj_dir/$proj_name.runs/impl_1/top_timing_summary_routed.rpt
report_timing -max_paths 25 -sort_by group -file $proj_dir/$proj_name.runs/impl_1/top_timing_paths_routed.rpt
report_utilization -file $proj_dir/$proj_name.runs/impl_1/top_utilization_routed.rpt

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
