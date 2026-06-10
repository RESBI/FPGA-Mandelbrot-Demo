set part_name "xc7z010clg400-1"
set proj_name "multicore_static_sim"
set proj_dir  "./multicore_static_sim_proj"
set rtl_dir   "./rtl"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_static.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_multicore_static [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
