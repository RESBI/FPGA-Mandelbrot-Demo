if {[info exists ::env(VIVADO_PART)]} {
    set part_name $::env(VIVADO_PART)
} else {
    set part_name "xczu4ev-sfvc784-1-i"
}
set rtl_dir   "./rtl"

set WORKER_CONTEXTS 4
set CORE_COUNT 4
set TEST_ROWS 12
set TEST_COLS 16
set TEST_MAX_ITER 64
set CORE_FIFO_DEPTH 128
set DYNAMIC_OWNER_DEPTH 4096
set TIMEOUT_CYCLES 2000000
set WORKER_MUL_LAT ""
set WORKER_ADD_LAT ""
set positional_idx 0
for {set arg_idx 0} {$arg_idx < [llength $argv]} {incr arg_idx} {
    set arg [lindex $argv $arg_idx]
    if {[string match "WORKER_CONTEXTS=*" $arg]} {
        set WORKER_CONTEXTS [string range $arg [string length "WORKER_CONTEXTS="] end]
    } elseif {[string match "CORE_COUNT=*" $arg]} {
        set CORE_COUNT [string range $arg [string length "CORE_COUNT="] end]
    } elseif {[string match "ROWS=*" $arg]} {
        set TEST_ROWS [string range $arg [string length "ROWS="] end]
    } elseif {[string match "COLS=*" $arg]} {
        set TEST_COLS [string range $arg [string length "COLS="] end]
    } elseif {[string match "MAX_ITER=*" $arg]} {
        set TEST_MAX_ITER [string range $arg [string length "MAX_ITER="] end]
    } elseif {[string match "CORE_FIFO_DEPTH=*" $arg]} {
        set CORE_FIFO_DEPTH [string range $arg [string length "CORE_FIFO_DEPTH="] end]
    } elseif {[string match "DYNAMIC_OWNER_DEPTH=*" $arg]} {
        set DYNAMIC_OWNER_DEPTH [string range $arg [string length "DYNAMIC_OWNER_DEPTH="] end]
    } elseif {[string match "TIMEOUT_CYCLES=*" $arg]} {
        set TIMEOUT_CYCLES [string range $arg [string length "TIMEOUT_CYCLES="] end]
    } elseif {[string match "WORKER_MUL_LAT=*" $arg]} {
        set WORKER_MUL_LAT [string range $arg [string length "WORKER_MUL_LAT="] end]
    } elseif {[string match "WORKER_ADD_LAT=*" $arg]} {
        set WORKER_ADD_LAT [string range $arg [string length "WORKER_ADD_LAT="] end]
    } elseif {$arg == "WORKER_CONTEXTS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set WORKER_CONTEXTS [lindex $argv $arg_idx]
    } elseif {$arg == "CORE_COUNT" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set CORE_COUNT [lindex $argv $arg_idx]
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
    } elseif {$arg == "DYNAMIC_OWNER_DEPTH" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set DYNAMIC_OWNER_DEPTH [lindex $argv $arg_idx]
    } elseif {$arg == "TIMEOUT_CYCLES" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TIMEOUT_CYCLES [lindex $argv $arg_idx]
    } elseif {$arg == "WORKER_MUL_LAT" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set WORKER_MUL_LAT [lindex $argv $arg_idx]
    } elseif {$arg == "WORKER_ADD_LAT" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set WORKER_ADD_LAT [lindex $argv $arg_idx]
    } elseif {[string is integer -strict $arg]} {
        if {$positional_idx == 0} {
            set WORKER_CONTEXTS $arg
        } elseif {$positional_idx == 1} {
            set CORE_COUNT $arg
        } elseif {$positional_idx == 2} {
            set TEST_ROWS $arg
        } elseif {$positional_idx == 3} {
            set TEST_COLS $arg
        } elseif {$positional_idx == 4} {
            set TEST_MAX_ITER $arg
        } elseif {$positional_idx == 5} {
            set CORE_FIFO_DEPTH $arg
        } elseif {$positional_idx == 6} {
            set DYNAMIC_OWNER_DEPTH $arg
        } elseif {$positional_idx == 7} {
            set TIMEOUT_CYCLES $arg
        }
        incr positional_idx
    }
}

set latency_suffix ""
if {$WORKER_MUL_LAT != "" || $WORKER_ADD_LAT != ""} {
    set latency_suffix "_ml${WORKER_MUL_LAT}_al${WORKER_ADD_LAT}"
}
set proj_name "multicore_dynamic_c${CORE_COUNT}_ctx${WORKER_CONTEXTS}${latency_suffix}_sim"
set proj_dir  "./multicore_dynamic_c${CORE_COUNT}_ctx${WORKER_CONTEXTS}${latency_suffix}_sim_proj"

puts "========================================"
puts " Dynamic multicore simulation"
puts " WORKER_CONTEXTS=$WORKER_CONTEXTS"
puts " CORE_COUNT=$CORE_COUNT"
puts " ROWS=$TEST_ROWS COLS=$TEST_COLS MAX_ITER=$TEST_MAX_ITER CORE_FIFO_DEPTH=$CORE_FIFO_DEPTH DYNAMIC_OWNER_DEPTH=$DYNAMIC_OWNER_DEPTH"
if {$WORKER_MUL_LAT != "" || $WORKER_ADD_LAT != ""} {
    puts " WORKER_MUL_LAT=$WORKER_MUL_LAT WORKER_ADD_LAT=$WORKER_ADD_LAT"
}
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_multicore_dynamic.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set verilog_defines {}
if {$WORKER_MUL_LAT != ""} {
    lappend verilog_defines "CFG_WORKER_MUL_LAT=$WORKER_MUL_LAT"
}
if {$WORKER_ADD_LAT != ""} {
    lappend verilog_defines "CFG_WORKER_ADD_LAT=$WORKER_ADD_LAT"
}
if {[llength $verilog_defines] > 0} {
    set_property verilog_define $verilog_defines [get_filesets sources_1]
    set_property verilog_define $verilog_defines [get_filesets sim_1]
}
set_property top tb_multicore_dynamic [get_filesets sim_1]
set_property generic "CORE_COUNT=$CORE_COUNT WORKER_CONTEXTS=$WORKER_CONTEXTS TEST_ROWS=$TEST_ROWS TEST_COLS=$TEST_COLS TEST_MAX_ITER=$TEST_MAX_ITER CORE_FIFO_DEPTH=$CORE_FIFO_DEPTH DYNAMIC_OWNER_DEPTH=$DYNAMIC_OWNER_DEPTH TIMEOUT_CYCLES=$TIMEOUT_CYCLES" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
