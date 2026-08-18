# ============================================================================
# fx600_coralnpu.xdc — pins and timing for Coral NPU on the Huawei FX600.
# Pin assignments are taken from Huawei's fpga-accel FX600 bare-metal reference
# design (fx600.xdc, Apache-2.0), reduced to the ports this design uses.
# ============================================================================

# ---- Board clock 100 MHz LVDS (bank 65) and reset ----
set_property PACKAGE_PIN AY23 [get_ports pin_sys_clk_p]
set_property PACKAGE_PIN BA23 [get_ports pin_sys_clk_n]
set_property IOSTANDARD  LVDS [get_ports pin_sys_clk_p]
set_property IOSTANDARD  LVDS [get_ports pin_sys_clk_n]
create_clock -period 10.000 -name pin_sys_clk_p [get_ports pin_sys_clk_p]

set_property PACKAGE_PIN AR26     [get_ports pin_reset_n]
set_property IOSTANDARD  LVCMOS12 [get_ports pin_reset_n]
set_false_path -from [get_ports pin_reset_n]

# ---- Activity LED (bank 64) ----
set_property PACKAGE_PIN BD23     [get_ports fpga_act]
set_property IOSTANDARD  LVCMOS18 [get_ports fpga_act]
set_false_path -to [get_ports fpga_act]

# ---- PCIe reference clock 100 MHz ----
set_property PACKAGE_PIN AP11 [get_ports pin_pcie_ref_clk_p]
set_property PACKAGE_PIN AP10 [get_ports pin_pcie_ref_clk_n]
create_clock -period 10.000 -name pin_pcie_ref_clk_p [get_ports pin_pcie_ref_clk_p]
set_input_jitter pin_pcie_ref_clk_p 0.100

# ---- PCIe lanes: on UltraScale+ the GT pins are implied by the PCIe block
# location. The XDMA IP is generated with the block/GT location matching the
# FX600 x16 slot; see build/gen_ip.tcl (PCIE_BLK_LOCN). If your Vivado reports
# a lane/pin conflict, take the LOC/PACKAGE_PIN lines for pin_pcie_* from
# Huawei's example project (component_example_prj.zip) and add them here.

# ---- Clock groups: core clock (MMCM from sysclk) is asynchronous to XDMA's
# 250 MHz axi_aclk; the AXI clock converter handles the crossing.
set_clock_groups -asynchronous \
  -group [get_clocks -of_objects [get_pins u_mmcm_core/CLKOUT0]] \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_xdma*/*bufg_gt_userclk/O}]] \
  -group [get_clocks pin_sys_clk_p]

# ---- Bitstream / config (from Huawei's fx600.xdc; needed for flash images) ----
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 21.3 [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK ENABLE [current_design]
set_property BITSTREAM.CONFIG.TIMER_CFG 32'h06000000 [current_design]
