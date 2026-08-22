# ============================================================================
# build.tcl — one-shot Vivado flow: RTL + IP -> bitstream + reports.
#
#   vivado -mode batch -source build/build.tcl -tclargs [scalar|rvv] [PART]
#
#   scalar (default) : CoreMiniAxi @ 62.5 MHz
#   rvv              : RvvCoreMiniAxi @ 25 MHz (MMCM divide 40)
#   PART             : default xcvu9p-flgb2104-2-i — the FX600's real part
#                      (confirmed; see docs/FX600_PART_AND_PINS.md). NOT flga2104.
#
# Outputs (all under build/out_<cfg>/):
#   fx600_coralnpu_<cfg>.bit      bitstream (JTAG load)
#   fx600_coralnpu_<cfg>.mcs      SPI flash image (optional persistence)
#   reports/*.rpt                 utilization (flat + hierarchical), timing, DRC
#   vivado.log                    full log
# ============================================================================

set cfg  [expr {[llength $argv] > 0 ? [lindex $argv 0] : "scalar"}]
set part [expr {[llength $argv] > 1 ? [lindex $argv 1] : ""}]

set root   [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root build out_$cfg]
file mkdir $outdir
file mkdir $outdir/reports

puts "INFO: cfg=$cfg part=$part root=$root"

# --- part selection: use the one given, else the first VU9P this Vivado offers --
if {$part eq ""} {
  set cands [lsort [get_parts -filter {DEVICE =~ xcvu9p*}]]
  if {[llength $cands] == 0} { puts "ERROR: no xcvu9p parts available in this Vivado"; exit 1 }
  # The FX600 is xcvu9p-flgb2104-2-i (see docs/FX600_PART_AND_PINS.md). Prefer it.
  if {[lsearch -exact $cands xcvu9p-flgb2104-2-i] >= 0} {
    set part xcvu9p-flgb2104-2-i
  } else {
    set part [lindex $cands 0]
    puts "WARNING: xcvu9p-flgb2104-2-i (the FX600's part) is not installed in this Vivado;"
    puts "WARNING: falling back to $part — pinned configs will NOT constrain correctly on it."
  }
  puts "INFO: no part given; auto-selected $part"
  puts "INFO: all VU9P parts available: $cands"
} elseif {[llength [get_parts $part]] == 0} {
  puts "ERROR: part $part not found. Available VU9P parts:"
  puts [lsort [get_parts -filter {DEVICE =~ xcvu9p*}]]
  exit 1
}

create_project -force -part $part fx600_coralnpu_$cfg $outdir/prj

# --- RTL sources ---------------------------------------------------------------
# cfg: scalar|rvv (JTAG-only top, default) or scalar_pcie|rvv_pcie (XDMA top)
set iface jtag
switch -glob $cfg {
  scalar       { set rtldir $root/rtl/scalar; set core_module CoreMiniAxi;    set core_div 16.0 }
  rvv          { set rtldir $root/rtl/rvv;    set core_module RvvCoreMiniAxi; set core_div 50.0 }
  scalar_selfclk { set rtldir $root/rtl/scalar; set core_module CoreMiniAxi;    set core_div 16.0; set iface selfclk }
  rvv_selfclk    { set rtldir $root/rtl/rvv;    set core_module RvvCoreMiniAxi; set core_div 50.0; set iface selfclk }
  scalar_pcie  { set rtldir $root/rtl/scalar; set core_module CoreMiniAxi;    set core_div 16.0; set iface pcie }
  rvv_pcie     { set rtldir $root/rtl/rvv;    set core_module RvvCoreMiniAxi; set core_div 40.0; set iface pcie }
  default { puts "ERROR: unknown cfg $cfg"; exit 1 }
}

# Packages and headers first (fpnew_pkg etc.), then everything else.
set svh   [lsort [glob -nocomplain $rtldir/*.svh]]
set pkgs  [lsort [glob -nocomplain $rtldir/*_pkg.sv]]
set rest  [lsort [glob -nocomplain $rtldir/*.sv $rtldir/*.v]]
foreach f $pkgs { set idx [lsearch -exact $rest $f]; if {$idx >= 0} { set rest [lreplace $rest $idx $idx] } }

add_files -norecurse [concat $pkgs $rest]
if {[llength $svh]} {
  add_files -norecurse $svh
  set_property file_type {Verilog Header} [get_files *.svh]
  foreach f [get_files *rvv_backend_config.svh] { set_property is_global_include true $f }
}
if {$iface eq "selfclk"} {
  add_files -norecurse [list $root/board/axi4_decerr_responder.sv $root/board/fx600_selfclk_top.sv]
  set_property top fx600_selfclk_top [current_fileset]
} elseif {$iface eq "jtag"} {
  add_files -norecurse [list $root/board/axi4_decerr_responder.sv $root/board/fx600_jtag_top.sv]
  set_property top fx600_jtag_top [current_fileset]
} else {
  add_files -norecurse [list $root/board/axil_to_core_axi4.sv $root/board/axi4_decerr_responder.sv $root/board/fx600_coralnpu_top.sv]
  set_property top fx600_coralnpu_top [current_fileset]
}
set_property include_dirs [list $rtldir] [current_fileset]
set_property file_type SystemVerilog [get_files *.v]

# Global defines: core module select + RVV backend config defines
set defs "CORE_MODULE=$core_module"
if {[string match rvv* $cfg]} { append defs " VLEN_128 ZVE32F_ON USE_GENERIC" }
set_property verilog_define $defs [current_fileset]

# Core clock divide for the MMCM (generic on the top). The selfclk variant has
# no MMCM and no parameters, so skip it there.
if {$iface ne "selfclk"} {
  set_property generic "CORE_CLKOUT_DIVIDE=$core_div" [current_fileset]
}

# --- constraints -----------------------------------------------------------------
if {$iface eq "selfclk"} {
  add_files -fileset constrs_1 -norecurse $root/board/fx600_selfclk.xdc
} elseif {$iface eq "jtag"} {
  add_files -fileset constrs_1 -norecurse $root/board/fx600_jtag.xdc
} else {
  add_files -fileset constrs_1 -norecurse $root/board/fx600_coralnpu.xdc
}

# --- IP ---------------------------------------------------------------------------
if {$iface eq "jtag" || $iface eq "selfclk"} { source $root/build/gen_ip_jtag.tcl } else { source $root/build/gen_ip.tcl }
generate_target all [get_ips]
# Synthesize IP out-of-context (standard Vivado flow)
foreach ip [get_ips] { create_ip_run [get_ips $ip] }
launch_runs [get_runs -filter {NAME =~ *synth_1 && NAME != synth_1}] -jobs 8
wait_on_run [get_runs -filter {NAME =~ *synth_1 && NAME != synth_1}]

# --- synthesis -----------------------------------------------------------------
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "ERROR: synthesis failed"; exit 1 }
open_run synth_1
# Optional: insert an ILA for on-hardware signal capture (set ILA=1 in the env)
if {[info exists ::env(ILA)] && $::env(ILA) eq "1"} {
  source $root/build/add_ila.tcl
  write_checkpoint -force $outdir/post_synth_ila.dcp
}
report_utilization -file $outdir/reports/util_synth.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $outdir/reports/util_hier_synth.rpt
close_design

# --- implementation --------------------------------------------------------------
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "ERROR: implementation failed"; exit 1 }

open_run impl_1
report_utilization -file $outdir/reports/util_impl.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $outdir/reports/util_hier_impl.rpt
report_timing_summary -delay_type max -max_paths 10 -file $outdir/reports/timing_impl.rpt
report_clock_utilization -file $outdir/reports/clocks.rpt
report_drc -file $outdir/reports/drc.rpt

# --- collect outputs -----------------------------------------------------------------
file copy -force [glob $outdir/prj/fx600_coralnpu_$cfg.runs/impl_1/*.bit] $outdir/fx600_coralnpu_$cfg.bit
# Optional SPI flash image. We never program flash on a borrowed card, so a
# failure here (e.g. SPI_BUSWIDTH not set in a minimal XDC) must not fail the build.
if {[catch {write_cfgmem -force -format mcs -size 128 -interface SPIx4 \
      -loadbit "up 0x0 $outdir/fx600_coralnpu_$cfg.bit" $outdir/fx600_coralnpu_$cfg.mcs} e]} {
  puts "INFO: .mcs flash image skipped (not needed for JTAG use): $e"
}

# WNS summary line for the issue reply
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "RESULT: cfg=$cfg part=$part WNS=$wns ns  bit=$outdir/fx600_coralnpu_$cfg.bit"
puts "BUILD_DONE"
