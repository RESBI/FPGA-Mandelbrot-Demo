set part_name "xczu4ev-sfvc784-1-i"
set rtl_dir "./rtl"
create_project -force tb_fx_tiny ./fx_tiny_sim_proj -part $part_name
set_property target_language Verilog [current_project]
add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_fx.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_multicore_fx [get_filesets sim_1]
set_property generic "CORE_COUNT=1 FX_CONTEXTS=4 TEST_ROWS=1 TEST_COLS=1 TEST_MAX_ITER=1 CORE_FIFO_DEPTH=4 TIMEOUT_CYCLES=100000" [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
restart
run all
