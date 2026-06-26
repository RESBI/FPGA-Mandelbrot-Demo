if {[info exists ::env(VIVADO_PART)]} {
    set part_name $::env(VIVADO_PART)
} else {
    set part_name "xczu4ev-sfvc784-1-i"
}
set rtl_dir   "./rtl"

set CONTEXTS 4
set TEST_ROWS 12
set TEST_COLS 160
set TEST_MAX_ITER 256
set TEST_ROW_START 0
set DEBUG_X -1
set STALL_AFTER -1
set STALL_CYCLES 0
set TIMEOUT_CYCLES 10000000

for {set arg_idx 0} {$arg_idx < [llength $argv]} {incr arg_idx} {
    set arg [lindex $argv $arg_idx]
    if {[string match "CONTEXTS=*" $arg]} {
        set CONTEXTS [string range $arg [string length "CONTEXTS="] end]
    } elseif {$arg == "CONTEXTS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set CONTEXTS [lindex $argv $arg_idx]
    } elseif {[string match "ROWS=*" $arg]} {
        set TEST_ROWS [string range $arg [string length "ROWS="] end]
    } elseif {$arg == "ROWS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_ROWS [lindex $argv $arg_idx]
    } elseif {[string match "COLS=*" $arg]} {
        set TEST_COLS [string range $arg [string length "COLS="] end]
    } elseif {$arg == "COLS" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_COLS [lindex $argv $arg_idx]
    } elseif {[string match "MAX_ITER=*" $arg]} {
        set TEST_MAX_ITER [string range $arg [string length "MAX_ITER="] end]
    } elseif {$arg == "MAX_ITER" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_MAX_ITER [lindex $argv $arg_idx]
    } elseif {[string match "ROW_START=*" $arg]} {
        set TEST_ROW_START [string range $arg [string length "ROW_START="] end]
    } elseif {$arg == "ROW_START" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TEST_ROW_START [lindex $argv $arg_idx]
    } elseif {[string match "DEBUG_X=*" $arg]} {
        set DEBUG_X [string range $arg [string length "DEBUG_X="] end]
    } elseif {$arg == "DEBUG_X" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set DEBUG_X [lindex $argv $arg_idx]
    } elseif {[string match "STALL_AFTER=*" $arg]} {
        set STALL_AFTER [string range $arg [string length "STALL_AFTER="] end]
    } elseif {$arg == "STALL_AFTER" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set STALL_AFTER [lindex $argv $arg_idx]
    } elseif {[string match "STALL_CYCLES=*" $arg]} {
        set STALL_CYCLES [string range $arg [string length "STALL_CYCLES="] end]
    } elseif {$arg == "STALL_CYCLES" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set STALL_CYCLES [lindex $argv $arg_idx]
    } elseif {[string match "TIMEOUT_CYCLES=*" $arg]} {
        set TIMEOUT_CYCLES [string range $arg [string length "TIMEOUT_CYCLES="] end]
    } elseif {$arg == "TIMEOUT_CYCLES" && $arg_idx + 1 < [llength $argv]} {
        incr arg_idx
        set TIMEOUT_CYCLES [lindex $argv $arg_idx]
    }
}

set proj_name "worker_kctx_sim"
set proj_dir  "./worker_kctx_sim_proj"

puts "========================================"
puts " Worker kctx simulation"
puts " CONTEXTS=$CONTEXTS ROWS=$TEST_ROWS COLS=$TEST_COLS ROW_START=$TEST_ROW_START MAX_ITER=$TEST_MAX_ITER DEBUG_X=$DEBUG_X"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob $rtl_dir/*.v]
add_files -fileset sim_1 ./sim/tb_worker_kctx.v
set_property include_dirs $rtl_dir [get_filesets sources_1]
set_property include_dirs $rtl_dir [get_filesets sim_1]
set_property top tb_worker_kctx [get_filesets sim_1]
set_property generic "CONTEXTS=$CONTEXTS TEST_ROWS=$TEST_ROWS TEST_COLS=$TEST_COLS TEST_MAX_ITER=$TEST_MAX_ITER TEST_ROW_START=$TEST_ROW_START DEBUG_X=$DEBUG_X STALL_AFTER=$STALL_AFTER STALL_CYCLES=$STALL_CYCLES TIMEOUT_CYCLES=$TIMEOUT_CYCLES" [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
restart
run all
