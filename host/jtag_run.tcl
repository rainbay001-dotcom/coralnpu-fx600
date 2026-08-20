# ============================================================================
# jtag_run.tcl — load and run a Coral NPU ELF over JTAG (no PCIe needed).
#
#   python3 host/elf2jtag.py elf/wfi_slot_0.elf > /tmp/prog.tcl
#   vivado -mode batch -source host/jtag_run.tcl -tclargs /tmp/prog.tcl [timeout_s] [dump_hexaddr dump_words]
#
# Protocol (same as every other Coral NPU host):
#   write segments -> PC @ 0x30004 -> 0x30000=1,0 -> poll 0x30008 bit0 (bit1=fault)
# Exit code: 0 clean halt, 2 fault, 3 timeout, 1 setup error.
# ============================================================================
set progfile  [lindex $argv 0]
set timeout_s [expr {[llength $argv] > 1 ? [lindex $argv 1] : 60}]
set dump_addr [expr {[llength $argv] > 2 ? [lindex $argv 2] : ""}]
set dump_n    [expr {[llength $argv] > 3 ? [lindex $argv 3] : 0}]

set CSR_RST 0x00030000
set CSR_PC  0x00030004
set CSR_ST  0x00030008

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xcvu9p*] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
current_hw_device $dev
refresh_hw_device $dev
set axi [lindex [get_hw_axis] 0]
if {$axi eq ""} { puts "ERROR: no JTAG-AXI core found — is the coralnpu bitstream programmed?"; exit 1 }
puts "INFO: using $axi on $dev"

proc w32 {addr val} {
  global axi
  create_hw_axi_txn -force txw $axi -type write -address [format %08x $addr] -len 1 -data [format %08x $val]
  run_hw_axi [get_hw_axi_txns txw]
}
proc r32 {addr} {
  global axi
  create_hw_axi_txn -force txr $axi -type read -address [format %08x $addr] -len 1
  run_hw_axi [get_hw_axi_txns txr]
  return 0x[get_property DATA [get_hw_axi_txns txr]]
}
proc wburst {addr nwords words} {
  # words: list of 8-hex-digit strings, lowest address first.
  # DATA is one hex string, LAST beat leftmost -> reverse the list.
  global axi
  set d ""
  foreach w $words { set d "$w$d" }
  create_hw_axi_txn -force txb $axi -type write -address [format %08x $addr] -len $nwords -burst INCR -data $d
  run_hw_axi [get_hw_axi_txns txb]
}
proc rburst {addr nwords} {
  global axi
  create_hw_axi_txn -force txrb $axi -type read -address [format %08x $addr] -len $nwords -burst INCR
  run_hw_axi [get_hw_axi_txns txrb]
  set d [get_property DATA [get_hw_axi_txns txrb]]
  set out {}
  set n [string length $d]
  for {set i 0} {$i < $nwords} {incr i} {
    set hi [expr {$n - 8*$i - 1}]; set lo [expr {$n - 8*$i - 8}]
    lappend out [string range $d $lo $hi]
  }
  return $out
}

# --- bus sanity: hold reset, scribble PC CSR, read it back -------------------
w32 $CSR_RST 1
w32 $CSR_PC  0xDEADBEEF
set rb [r32 $CSR_PC]
puts "bus check: wrote 0xDEADBEEF to START_PC, read $rb [expr {$rb == 0xdeadbeef || $rb == 0xDEADBEEF ? "(OK)" : "(MISMATCH)"}]"
if {[expr $rb] != [expr 0xDEADBEEF]} { puts "ERROR: bus check failed"; exit 1 }

# --- load program ------------------------------------------------------------
source $progfile   ;# sets: entry, segs
set t0 [clock milliseconds]
set total 0
foreach s $segs {
  lassign $s a n w
  wburst $a $n $w
  incr total $n
  # spot-check first word of each burst via independent single read
  set exp 0x[lindex $w 0]
  set got [r32 $a]
  if {[expr $got] != [expr $exp]} { puts "ERROR: verify @$a expected $exp got $got"; exit 1 }
}
puts "loaded $total words in [expr {[clock milliseconds]-$t0}] ms (spot-verified per burst)"
puts "entry point $entry"

# --- boot --------------------------------------------------------------------
w32 $CSR_PC  $entry
w32 $CSR_RST 1
w32 $CSR_RST 0
puts "core released"

# --- poll --------------------------------------------------------------------
set t0 [clock seconds]
while {1} {
  set st [r32 $CSR_ST]
  if {[expr $st & 1]} break
  if {[expr [clock seconds] - $t0] > $timeout_s} {
    puts "TIMEOUT after ${timeout_s}s (status=$st)"; exit 3
  }
  after 100
}
set fault [expr {($st >> 1) & 1}]
puts "halted, status=$st ([expr {$fault ? "FAULT" : "clean"}])"

# --- optional dump -----------------------------------------------------------
if {$dump_addr ne ""} {
  puts "memory dump @ $dump_addr:"
  set words [rburst $dump_addr $dump_n]
  set a [expr $dump_addr]
  foreach w $words { puts [format "  0x%08x: 0x%s" $a $w]; incr a 4 }
}

close_hw_manager
exit [expr {$fault ? 2 : 0}]
