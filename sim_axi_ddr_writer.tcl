if {[info exists ::env(TEMP)]} {
    set temp_root $::env(TEMP)
} else {
    set temp_root "/tmp"
}
set proj_dir [file normalize [file join $temp_root mandelbrot_sim_axi_ddr_writer]]
create_project -force sim_axi_ddr_writer $proj_dir -part xczu4ev-sfvc784-2-i
set_property include_dirs ./rtl [current_fileset]
add_files -fileset sources_1 {./rtl/queue.v ./rtl/axi_ddr_writer.v}
add_files -fileset sim_1 {./sim/tb_axi_ddr_writer.v}
set_property top tb_axi_ddr_writer [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property xsim.simulate.runtime 10us [get_filesets sim_1]
launch_simulation
close_sim
close_project
quit
