# gen_ip_jtag.tcl — IPs for the JTAG-only top: jtag_axi (AXI4, bursts) and a
# 32->128 width converter. Sourced by build.tcl inside an open project.
if {[llength [get_ips jtag_axi_0]] == 0} {
  create_ip -name jtag_axi -vendor xilinx.com -library ip -module_name jtag_axi_0
}
set_property -dict [list \
  CONFIG.PROTOCOL      {0} \
  CONFIG.M_AXI_ADDR_WIDTH {32} \
] [get_ips jtag_axi_0]
# PROTOCOL 0 = AXI4 (bursts). Data width is fixed at 32.

if {[llength [get_ips axi_dwidth_0]] == 0} {
  create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -module_name axi_dwidth_0
}
set_property -dict [list \
  CONFIG.PROTOCOL        {AXI4} \
  CONFIG.SI_DATA_WIDTH   {32} \
  CONFIG.MI_DATA_WIDTH   {128} \
  CONFIG.ADDR_WIDTH      {32} \
  CONFIG.SI_ID_WIDTH     {0} \
  CONFIG.ACLK_ASYNC      {0} \
] [get_ips axi_dwidth_0]
puts "INFO: JTAG-mode IPs configured (jtag_axi_0, axi_dwidth_0)"
