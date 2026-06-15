set part_name "xc7k70tfbg676-1"
set rtl_dir   "./rtl"

set WORKER_CONTEXTS 4
foreach arg $argv {
    if {[string match "WORKER_CONTEXTS=*" $arg]} {
        set WORKER_CONTEXTS [string range $arg [string length "WORKER_CONTEXTS="] end]
    } elseif {[string is integer -strict $arg]} {
        set WORKER_CONTEXTS $arg
    }
}

set proj_name "multicore_dynamic_ctx${WORKER_CONTEXTS}_sim"
set proj_dir  "./multicore_dynamic_ctx${WORKER_CONTEXTS}_sim_proj"

puts "========================================"
puts " Dynamic multicore simulation"
puts " WORKER_CONTEXTS=$WORKER_CONTEXTS"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_dynamic.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_multicore_dynamic [get_filesets sim_1]
set_property generic "WORKER_CONTEXTS=$WORKER_CONTEXTS" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
