set part_name "xc7k70tfbg676-1"
set proj_name "tx_ctrl_tiled_sim"
set proj_dir  "./tx_ctrl_tiled_sim_proj"
set rtl_dir   "./rtl"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list $rtl_dir/tx_ctrl.v]
add_files -fileset sim_1 ./sim/tb_tx_ctrl_tiled.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_tx_ctrl_tiled [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
