set part_name "xc7k70tfbg676-1"
set rtl_dir   "./rtl"

create_project -force fp_latency_sim ./fp_latency_sim_proj -part $part_name
set_property target_language Verilog [current_project]
add_files -fileset sources_1 [list $rtl_dir/fp_mul.v $rtl_dir/fp_add.v]
add_files -fileset sim_1 ./sim/tb_fp_latency.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_fp_latency [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
