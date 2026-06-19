set part_name "xc7k70tfbg676-1"
set rtl_dir   "./rtl"

set WORKER_CONTEXTS 4
set TEST_ROWS 12
set TEST_COLS 16
set TEST_MAX_ITER 64
set CORE_FIFO_DEPTH 128
set TIMEOUT_CYCLES 2000000
set positional_idx 0
for {set arg_idx 0} {$arg_idx < [llength $argv]} {incr arg_idx} {
    set arg [lindex $argv $arg_idx]
    if {[string match "WORKER_CONTEXTS=*" $arg]} {
        set WORKER_CONTEXTS [string range $arg [string length "WORKER_CONTEXTS="] end]
    } elseif {[string match "ROWS=*" $arg]} {
        set TEST_ROWS [string range $arg [string length "ROWS="] end]
    } elseif {[string match "COLS=*" $arg]} {
        set TEST_COLS [string range $arg [string length "COLS="] end]
    } elseif {[string match "MAX_ITER=*" $arg]} {
        set TEST_MAX_ITER [string range $arg [string length "MAX_ITER="] end]
    } elseif {[string match "CORE_FIFO_DEPTH=*" $arg]} {
        set CORE_FIFO_DEPTH [string range $arg [string length "CORE_FIFO_DEPTH="] end]
    } elseif {[string match "TIMEOUT_CYCLES=*" $arg]} {
        set TIMEOUT_CYCLES [string range $arg [string length "TIMEOUT_CYCLES="] end]
    } elseif {$arg == "WORKER_CONTEXTS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set WORKER_CONTEXTS [lindex $argv $arg_idx]
    } elseif {$arg == "ROWS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_ROWS [lindex $argv $arg_idx]
    } elseif {$arg == "COLS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_COLS [lindex $argv $arg_idx]
    } elseif {$arg == "MAX_ITER" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_MAX_ITER [lindex $argv $arg_idx]
    } elseif {$arg == "CORE_FIFO_DEPTH" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set CORE_FIFO_DEPTH [lindex $argv $arg_idx]
    } elseif {$arg == "TIMEOUT_CYCLES" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TIMEOUT_CYCLES [lindex $argv $arg_idx]
    } elseif {[string is integer -strict $arg]} {
        if {$positional_idx == 0} {
            set WORKER_CONTEXTS $arg
        } elseif {$positional_idx == 1} {
            set TEST_ROWS $arg
        } elseif {$positional_idx == 2} {
            set TEST_COLS $arg
        } elseif {$positional_idx == 3} {
            set TEST_MAX_ITER $arg
        } elseif {$positional_idx == 4} {
            set CORE_FIFO_DEPTH $arg
        } elseif {$positional_idx == 5} {
            set TIMEOUT_CYCLES $arg
        }
        incr positional_idx
    }
}

set proj_name "multicore_dynamic_ctx${WORKER_CONTEXTS}_sim"
set proj_dir  "./multicore_dynamic_ctx${WORKER_CONTEXTS}_sim_proj"

puts "========================================"
puts " Dynamic multicore simulation"
puts " WORKER_CONTEXTS=$WORKER_CONTEXTS"
puts " ROWS=$TEST_ROWS COLS=$TEST_COLS MAX_ITER=$TEST_MAX_ITER CORE_FIFO_DEPTH=$CORE_FIFO_DEPTH"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_dynamic.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_multicore_dynamic [get_filesets sim_1]
set_property generic "WORKER_CONTEXTS=$WORKER_CONTEXTS TEST_ROWS=$TEST_ROWS TEST_COLS=$TEST_COLS TEST_MAX_ITER=$TEST_MAX_ITER CORE_FIFO_DEPTH=$CORE_FIFO_DEPTH TIMEOUT_CYCLES=$TIMEOUT_CYCLES" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
