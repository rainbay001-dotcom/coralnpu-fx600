# ============================================================================
# gen_ip.tcl — create the two Xilinx IPs the FX600 top instantiates.
# Sourced by build.tcl inside an open project. Safe to re-run.
#
#   xdma_0      : PCIe Gen3 x16 endpoint with AXI-Lite master on BAR0
#   axil_cdc_0  : AXI4-Lite async clock converter (XDMA 250 MHz -> core clock)
#
# PCIE_BLK_LOCN: the FX600 x16 slot uses one of the VU9P's PCIe hard blocks.
# Huawei's example project pins it; if you have that project open, read
# CONFIG.pcie_blk_locn from its XDMA IP and set it below. X1Y2 is the usual
# choice for the x16 edge connector on VU9P FLGB2104 boards; Vivado will error
# clearly if the GT quads don't match the reference-clock pin (AP10/AP11), in
# which case try X0Y1 / X1Y0 as reported by the IP customization GUI.
# ============================================================================

set PCIE_BLK_LOCN "X1Y2"

# ---- XDMA -------------------------------------------------------------------
if {[llength [get_ips xdma_0]] == 0} {
  create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
}
set_property -dict [list \
  CONFIG.mode_selection            {Advanced} \
  CONFIG.pl_link_cap_max_link_width {X16} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
  CONFIG.axi_data_width            {64_bit} \
  CONFIG.axisten_freq              {250} \
  CONFIG.pcie_blk_locn             $PCIE_BLK_LOCN \
  CONFIG.pf0_device_id             {9038} \
  CONFIG.pf0_subsystem_id          {0007} \
  CONFIG.pf0_msix_enabled          {false} \
  CONFIG.xdma_num_usr_irq          {1} \
  CONFIG.xdma_rnum_chnl            {1} \
  CONFIG.xdma_wnum_chnl            {1} \
  CONFIG.axilite_master_en         {true} \
  CONFIG.axilite_master_size       {1} \
  CONFIG.axilite_master_scale      {Megabytes} \
  CONFIG.pf0_msi_enabled           {false} \
  CONFIG.PF0_DEVICE_ID_mqdma       {9038} \
  CONFIG.PF2_DEVICE_ID_mqdma       {9038} \
  CONFIG.PF3_DEVICE_ID_mqdma       {9038} \
  CONFIG.plltype                   {QPLL1} \
  CONFIG.en_gt_selection           {true} \
  CONFIG.select_quad               {GTY_Quad_227} \
] [get_ips xdma_0]

# ---- AXI-Lite clock converter --------------------------------------------------
if {[llength [get_ips axil_cdc_0]] == 0} {
  create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name axil_cdc_0
}
set_property -dict [list \
  CONFIG.PROTOCOL     {AXI4LITE} \
  CONFIG.ADDR_WIDTH   {32} \
  CONFIG.DATA_WIDTH   {32} \
  CONFIG.ID_WIDTH     {0} \
  CONFIG.ACLK_ASYNC   {1} \
  CONFIG.ACLK_RATIO   {1:2} \
] [get_ips axil_cdc_0]

puts "INFO: IPs configured (xdma_0 @ $PCIE_BLK_LOCN, axil_cdc_0)"
