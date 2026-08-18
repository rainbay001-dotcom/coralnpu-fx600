# Program the FX600 over JTAG from the command line.
#   vivado -mode batch -source build/program.tcl -tclargs <path/to/bitstream.bit>
set bit [lindex $argv 0]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xcvu9p*] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED $dev with $bit"
close_hw_manager
