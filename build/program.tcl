# Program the FX600 over JTAG from the command line.
#   vivado -mode batch -source build/program.tcl -tclargs <path/to/bitstream.bit>
set bit [lindex $argv 0]
# --- Vivado version compatibility shims (2018.x uses open_hw/close_hw) -------
proc hw_open {} {
  if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }
}
proc hw_close {} {
  if {[llength [info commands close_hw_manager]]} { close_hw_manager } else { close_hw }
}
proc hw_connect {} {
  if {[catch {connect_hw_server -allow_non_jtag}]} { connect_hw_server }
}
hw_open
hw_connect
open_hw_target
set dev [lindex [get_hw_devices xcvu9p*] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED $dev with $bit"
hw_close
