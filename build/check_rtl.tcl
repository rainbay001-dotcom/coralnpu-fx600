# ============================================================================
# check_rtl.tcl — FAST compatibility test: can this Vivado even parse the RTL?
#
#   vivado -mode batch -source build/check_rtl.tcl -tclargs [scalar|rvv] [PART]
#
# Elaborates the core only (no IP, no place & route). Takes ~2-10 minutes and
# tells us, before any long build, whether this Vivado version understands the
# SystemVerilog. Run this FIRST on any new/old Vivado.
# ============================================================================
set cfg  [expr {[llength $argv] > 0 ? [lindex $argv 0] : "scalar"}]
set part [expr {[llength $argv] > 1 ? [lindex $argv 1] : ""}]

set root [file normalize [file join [file dirname [info script]] ..]]
puts "INFO: Vivado [version -short], cfg=$cfg"

# Pick a part automatically if not given.
if {$part eq ""} {
  set cands [get_parts -filter {DEVICE =~ xcvu9p*}]
  if {[llength $cands] == 0} {
    puts "ERROR: this Vivado has no xcvu9p parts installed/licensed."
    puts "Installed UltraScale+ VU devices: [lsort -unique [get_property DEVICE [get_parts -filter {DEVICE =~ xcvu*}]]]"
    exit 1
  }
  set part [lindex [lsort $cands] 0]
}
puts "INFO: part=$part"

switch -glob $cfg {
  scalar* { set rtldir $root/rtl/scalar; set top CoreMiniAxi }
  rvv*    { set rtldir $root/rtl/rvv;    set top RvvCoreMiniAxi }
  default { puts "ERROR: unknown cfg $cfg"; exit 1 }
}

set outdir $root/build/check_$cfg
file mkdir $outdir
create_project -force -part $part check_$cfg $outdir/prj

set svh  [lsort [glob -nocomplain $rtldir/*.svh]]
set pkgs [lsort [glob -nocomplain $rtldir/*_pkg.sv]]
set rest [lsort [glob -nocomplain $rtldir/*.sv $rtldir/*.v]]
foreach f $pkgs { set i [lsearch -exact $rest $f]; if {$i >= 0} { set rest [lreplace $rest $i $i] } }

add_files -norecurse [concat $pkgs $rest]
if {[llength $svh]} {
  add_files -norecurse $svh
  set_property file_type {Verilog Header} [get_files *.svh]
  # The Chisel-generated RVV config header is included by nothing; force it global.
  foreach f [get_files *rvv_backend_config.svh] { set_property is_global_include true $f }
}
set_property include_dirs [list $rtldir] [current_fileset]
set_property top $top [current_fileset]

set defs ""
if {[string match rvv* $cfg]} { set defs "VLEN_128 ZVE32F_ON USE_GENERIC" }
if {$defs ne ""} { set_property verilog_define $defs [current_fileset] }

puts "INFO: elaborating $top ... (parse errors, if any, appear below)"
if {[catch {synth_design -top $top -part $part -mode out_of_context -rtl -name rtl_check} err]} {
  puts "PARSE_FAILED: $err"
  puts "CHECK_DONE fail"
  exit 1
}
puts "PARSE_OK: $top elaborated cleanly on Vivado [version -short]"
puts "CHECK_DONE ok"
exit 0
