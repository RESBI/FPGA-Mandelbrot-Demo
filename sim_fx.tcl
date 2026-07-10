set part_name "xczu4ev-sfvc784-1-i"
set rtl_dir   "./rtl"

create_project -force tb_fx_sim ./fx_sim_proj -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_fx.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_multicore_fx [get_filesets sim_1]
set_property generic "CORE_COUNT=4 FX_CONTEXTS=4 TEST_ROWS=12 TEST_COLS=16 TEST_MAX_ITER=64 CORE_FIFO_DEPTH=128 TIMEOUT_CYCLES=2000000" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
