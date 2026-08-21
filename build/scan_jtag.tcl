# scan_jtag.tcl — does this node see a JTAG cable and an FPGA?
#   vivado -mode batch -nolog -nojournal -source build/scan_jtag.tcl
proc hw_open {} { if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw } }
proc hw_connect {} { if {[catch {connect_hw_server -allow_non_jtag}]} { connect_hw_server } }
puts "INFO: host [exec hostname], Vivado [version -short]"
hw_open
if {[catch {hw_connect} e]} { puts "NO_HW_SERVER: $e"; puts "SCAN_DONE none"; exit 1 }
set targets [get_hw_targets]
if {[llength $targets] == 0} {
  puts "NO_JTAG_TARGET: hw_server started but no cable/target found on this node."
  puts "SCAN_DONE none"; exit 1
}
puts "TARGETS: $targets"
foreach t $targets {
  current_hw_target $t
  if {[catch {open_hw_target} e]} { puts "  (cannot open $t: $e)"; continue }
  foreach d [get_hw_devices] {
    puts "  DEVICE: $d  part=[get_property PART $d]  idcode=[get_property IDCODE $d]"
  }
  close_hw_target
}
puts "SCAN_DONE ok"
exit 0
