# fx600_jtag.xdc — pins/timing for the JTAG-only Coral NPU top.
# Only three board connections: 100 MHz LVDS clock, reset, activity LED.
set_property PACKAGE_PIN AY23 [get_ports pin_sys_clk_p]
set_property PACKAGE_PIN BA23 [get_ports pin_sys_clk_n]
set_property IOSTANDARD  LVDS [get_ports pin_sys_clk_p]
set_property IOSTANDARD  LVDS [get_ports pin_sys_clk_n]
create_clock -period 10.000 -name pin_sys_clk_p [get_ports pin_sys_clk_p]

set_property PACKAGE_PIN AR26     [get_ports pin_reset_n]
set_property IOSTANDARD  LVCMOS12 [get_ports pin_reset_n]
set_false_path -from [get_ports pin_reset_n]

set_property PACKAGE_PIN BD23     [get_ports fpga_act]
set_property IOSTANDARD  LVCMOS18 [get_ports fpga_act]
set_false_path -to [get_ports fpga_act]

# JTAG-AXI's debug hub clock: connect to the free-running core clock.
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_core]

# Bitstream/config (from Huawei's fx600.xdc)
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
