connect -url tcp:localhost:3121
targets 4
puts "DDR full burst read 0x10000000..0x10000080:"
for {set i 0} {$i < 16} {incr i} {
    set addr [expr {0x10000000 + $i * 8}]
    set val [mrd -force $addr]
    puts [format "  beat %2d 0x%08X: %s" $i $addr $val]
}
disconnect
