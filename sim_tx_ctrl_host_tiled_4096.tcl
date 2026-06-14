set part_name "xc7z010clg400-1"
set proj_name "tx_ctrl_host_tiled_4096_sim"
set proj_dir  "./tx_ctrl_host_tiled_4096_sim_proj"
set rtl_dir   "./rtl"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list $rtl_dir/tx_ctrl.v]
add_files -fileset sim_1 ./sim/tb_tx_ctrl_host_tiled_4096.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_tx_ctrl_host_tiled_4096 [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
