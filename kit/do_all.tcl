# ============================================================================
# do_all.tcl — program the FX600 with Coral NPU and run a test program.
# Works on any Vivado from ~2015 onward (command names are probed, not assumed)
# and is GUI-safe (never calls exit, so it won't close your Vivado).
#
#   GUI Tcl Console:  cd {C:/path/to/kit} ; source do_all.tcl
#   Command line:     vivado -mode batch -source do_all.tcl
#   Windows:          double-click run_all.bat
#
# Optional: set ::prog before sourcing to pick a different test program, e.g.
#   set ::prog prog_align_test.tcl ; source do_all.tcl
# ============================================================================

set here [file dirname [file normalize [info script]]]
cd $here
if {![info exists ::prog]} { set ::prog prog_wfi_slot_0.tcl }

puts "======================================================================"
puts " Coral NPU on FX600 — Vivado [version -short] — dir: $here"
puts "======================================================================"

# ---- open the hardware manager (name differs before/after 2019.2) ----------
if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }
if {[catch {connect_hw_server -allow_non_jtag}]} {
  if {[catch {connect_hw_server} e]} { puts "ERROR: cannot start hw_server: $e"; return }
}
if {[catch {open_hw_target} e]} { puts "ERROR: no JTAG target found: $e"; return }

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} { puts "ERROR: no FPGA on the JTAG chain"; return }
current_hw_device $dev
puts "DEVICE:   $dev"
puts "PART:     [get_property PART $dev]"
puts "IDCODE:   [get_property IDCODE $dev]"

# ---- program ---------------------------------------------------------------
set bit [lindex [lsort [glob -nocomplain *.bit]] 0]
if {$bit eq ""} { puts "ERROR: no .bit file in $here"; return }
puts "BITSTREAM: $bit"
set_property PROGRAM.FILE $bit $dev
if {[catch {program_hw_devices $dev} e]} { puts "ERROR: programming failed: $e"; return }
refresh_hw_device $dev
puts "PROGRAMMED: ok"

# ---- find the JTAG-AXI master inserted by our design ------------------------
set axi [lindex [get_hw_axis -quiet] 0]
puts "AXI CORE: '$axi'"
if {$axi eq ""} {
  puts "STOP: programming succeeded but no JTAG-AXI core is visible."
  puts "      This Vivado's Hardware Manager is probably older than the one that"
  puts "      built the bitstream. Report this line and we will rebuild to match."
  return
}

proc w32 {addr val} { global axi
  create_hw_axi_txn -force t_w $axi -type write -address [format %08x $addr] -len 1 -data [format %08x $val]
  run_hw_axi -quiet [get_hw_axi_txns t_w] }
proc r32 {addr} { global axi
  create_hw_axi_txn -force t_r $axi -type read -address [format %08x $addr] -len 1
  run_hw_axi -quiet [get_hw_axi_txns t_r]
  return 0x[get_property DATA [get_hw_axi_txns t_r]] }
proc wburst {addr n words} { global axi
  set d ""; foreach w $words { set d "$w$d" }
  create_hw_axi_txn -force t_b $axi -type write -address [format %08x $addr] -len $n -burst INCR -data $d
  run_hw_axi -quiet [get_hw_axi_txns t_b] }

# ---- bus sanity ------------------------------------------------------------
w32 0x00030000 1
w32 0x00030004 0xDEADBEEF
set rb [r32 0x00030004]
puts "BUS CHECK: wrote 0xDEADBEEF, read $rb"
if {[expr $rb] != [expr 0xDEADBEEF]} { puts "STOP: bus check failed"; return }

# ---- load the program ------------------------------------------------------
puts "LOADING:  $::prog"
source $::prog
set t0 [clock milliseconds]
foreach s $segs { lassign $s a n w; wburst $a $n $w }
puts "LOADED:   [llength $segs] bursts in [expr {[clock milliseconds]-$t0}] ms"

# ---- boot and wait ---------------------------------------------------------
w32 0x00030004 $entry
w32 0x00030000 1
w32 0x00030000 0
puts "RELEASED: core started at $entry"

set st 0
for {set i 0} {$i < 600} {incr i} {
  set st [r32 0x00030008]
  if {[expr $st & 1]} break
  after 100
}
if {[expr $st & 1]} {
  if {[expr ($st >> 1) & 1]} {
    puts "RESULT:   STATUS=$st  -> HALTED WITH FAULT"
  } else {
    puts "RESULT:   STATUS=$st  -> HALTED CLEAN  *** Coral NPU ran successfully ***"
  }
} else {
  puts "RESULT:   STATUS=$st  -> TIMEOUT (core never halted)"
}
puts "======================================================================"
