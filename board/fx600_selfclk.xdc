# fx600_selfclk.xdc — constraints for the zero-I/O variant.
# The only clock is the internal configuration oscillator (STARTUPE3/CFGMCLK).
# Nominal ~50 MHz; constrain conservatively at 20 ns so the /2 core clock is ~25 MHz.
create_clock -period 20.000 -name cfgmclk [get_pins u_startup/CFGMCLK]

# Safety on an unknown package: leave every unused pin high-Z rather than pulled.
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# JTAG-AXI debug hub runs on the core clock.
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]

# Needed only if you ever want a .mcs flash image (we normally don't):
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 21.3 [current_design]
