set part_name "xc7k70tfbg676-1"
set rtl_dir   "./rtl"

set TEST_ROWS 12
set TEST_COLS 160
set TEST_MAX_ITER 256
set TEST_ROW_START 0
set TIMEOUT_CYCLES 10000000

foreach arg $argv {
    if {[string match "ROWS=*" $arg]} {
        set TEST_ROWS [string range $arg [string length "ROWS="] end]
    } elseif {[string match "COLS=*" $arg]} {
        set TEST_COLS [string range $arg [string length "COLS="] end]
    } elseif {[string match "MAX_ITER=*" $arg]} {
        set TEST_MAX_ITER [string range $arg [string length "MAX_ITER="] end]
    } elseif {[string match "ROW_START=*" $arg]} {
        set TEST_ROW_START [string range $arg [string length "ROW_START="] end]
    } elseif {[string match "TIMEOUT_CYCLES=*" $arg]} {
        set TIMEOUT_CYCLES [string range $arg [string length "TIMEOUT_CYCLES="] end]
    }
}

set proj_name "worker_2ctx_sim"
set proj_dir  "./worker_2ctx_sim_proj"

puts "========================================"
puts " Worker 2ctx simulation"
puts " ROWS=$TEST_ROWS COLS=$TEST_COLS ROW_START=$TEST_ROW_START MAX_ITER=$TEST_MAX_ITER"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_worker_2ctx.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_worker_2ctx [get_filesets sim_1]
set_property generic "TEST_ROWS=$TEST_ROWS TEST_COLS=$TEST_COLS TEST_MAX_ITER=$TEST_MAX_ITER TEST_ROW_START=$TEST_ROW_START TIMEOUT_CYCLES=$TIMEOUT_CYCLES" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
