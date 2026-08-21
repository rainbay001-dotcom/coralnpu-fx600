# ============================================================================
# add_ila.tcl — insert an ILA (抓线 on real hardware) into the synthesized design.
# Sourced by build.tcl when ILA=1 is set in the environment, e.g.
#   ILA=1 vivado -mode batch -source build/build.tcl -tclargs scalar <part>
#
# Captures, on the core clock: reset, halted/fault/wfi, and both AXI channels
# between the JTAG-AXI bridge and the core. 4096 samples deep.
# After programming, open Vivado GUI -> Hardware Manager -> the ILA appears.
# ============================================================================
set depth 4096
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH $depth [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false   [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER true  [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets -hierarchical -filter {NAME =~ *clk_core*} ]

proc add_probe {idx nets} {
  if {[llength $nets] == 0} { puts "INFO: probe$idx skipped (no nets matched)"; return }
  if {$idx > 0} { create_debug_port u_ila_0 probe }
  set_property port_width [llength $nets] [get_debug_ports u_ila_0/probe$idx]
  connect_debug_port u_ila_0/probe$idx $nets
  puts "INFO: probe$idx <- [llength $nets] net(s)"
}

set i 0
foreach pat {core_halted core_fault core_wfi core_aresetn
             s_awvalid s_awready s_wvalid s_wready s_bvalid
             s_arvalid s_arready s_rvalid s_rready} {
  add_probe $i [get_nets -quiet -hierarchical -filter "NAME =~ *$pat*"]
  incr i
}
add_probe $i [get_nets -quiet -hierarchical -filter {NAME =~ *s_awaddr[*]}] ; incr i
add_probe $i [get_nets -quiet -hierarchical -filter {NAME =~ *s_araddr[*]}]
puts "INFO: ILA inserted (depth $depth)"
