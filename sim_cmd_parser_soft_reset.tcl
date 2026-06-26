if {[info exists ::env(VIVADO_PART)]} {
    set part_name $::env(VIVADO_PART)
} else {
    set part_name "xczu4ev-sfvc784-1-i"
}
set proj_name "cmd_parser_soft_reset_sim"
set proj_dir  "./cmd_parser_soft_reset_sim_proj"
set rtl_dir   "./rtl"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list $rtl_dir/cmd_parser.v]
add_files -fileset sim_1 ./sim/tb_cmd_parser_soft_reset.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_cmd_parser_soft_reset [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
quit
