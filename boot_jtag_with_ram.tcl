connect -url tcp:localhost:3121

set bit_file     "./mandelbrot_with_ram_proj/mandelbrot_with_ram.runs/impl_1/system_wrapper.bit"
set psu_init_tcl "./psu_init_with_ram.tcl"

if {![file exists $bit_file]}     { puts "ERROR: bitstream not found"; exit 1 }
if {![file exists $psu_init_tcl]} { puts "ERROR: psu_init_with_ram.tcl not found"; exit 1 }

puts "Step 1: System reset APU..."
targets 8
rst -system

puts "Step 2: Sourcing psu_init_with_ram.tcl..."
targets 4

proc mask_write { addr mask value } {
    set curval "0x[string range [mrd -force $addr] end-8 end]"
    set curval [expr {$curval & ~($mask)}]
    set maskedval [expr {$value & $mask}]
    set maskedval [expr {$curval | $maskedval}]
    mwr -force $addr $maskedval
}

source $psu_init_tcl
psu_init
puts "psu_init done."

if {[catch {psu_post_config} err]} { puts "psu_post_config: $err" }
if {[catch {psu_ps_pl_reset_config} err]} { puts "psu_ps_pl_reset_config: $err" }
if {[catch {psu_ps_pl_isolation_removal} err]} { puts "psu_ps_pl_isolation_removal: $err" }

puts "Verifying DDR..."
mwr -force 0x10000000 0xDEADBEEF
after 100
set val [mrd -force 0x10000000]
puts "DDR readback: $val"

puts "Step 4: Programming bitstream..."
targets -set -nocase -filter {name =~ "PS TAP"}
fpga $bit_file
puts "Bitstream programmed."
after 500

puts "Boot complete. PS DDR initialized, PL Mandelbrot running."
disconnect
