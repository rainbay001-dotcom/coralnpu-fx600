# FX600: the FPGA part is `xcvu9p-flgb2104-2-i` (not flga2104)

Resolved 2026-08-22 after the pinned build failed DRC UCIO-1 on `xcvu9p-flga2104-1-e`.

## Evidence

1. **Huawei's own FX600 driver** — `FX600/sdaccel/software/kernel_drivers/xclmgmt/driver/xclng/mgmt/mgmt-core.c:279`
   in github.com/Huawei/fpga-accel:  `//FPGAPartName is: xcvu9p-flgb2104-2-i`
2. **Huawei Cloud FPGA FAQ** (github.com/huaweicloud/huaweicloud-fpga/FAQs.md):
   *"Currently, Huawei Cloud FPGA uses Xilinx UltraScale+ series xcvu9p-flgb2104-2-i cards."*
   The FP1 repo's `lib/scripts/build_facs.tcl` / `init_ip.tcl` also name flgb2104.
3. **The FP1 instance card IS the FX600**: the FP1 repo's `lib/constraints/ddr{a,b,d}_pin_x8.xdc`
   use exactly the FX600's DDR reference-clock pins (BA35/BB35, C38/C39, J19/J20).
4. **AMD's official package pinout files** (`xcvu9p{flga,flgb}2104pkg.txt`, from
   https://www.xilinx.com/support/packagefiles/usapackages/) show Huawei's pin choices only make
   electrical sense in **flgb2104**:

   | Ball | Huawei FX600 use | flgb2104 (AMD) | flga2104 (AMD) |
   |---|---|---|---|
   | AY23 | sys_clk_p (LVDS) | `IO_L12P_T1U_N10_GC_64` — clock-capable P | `IO_L11N_T1U_N9_GC_64` — an N pin |
   | BA23 | sys_clk_n (LVDS) | `IO_L12N_T1U_N11_GC_64` — its N pair | **`VCCO_64` — a power ball** |
   | AR26 | reset_n (LVCMOS12) | `IO_T3U_N12_PERSTN0_65` — PCIe PERST# | **`GND`** |
   | BD23 | activity LED | `IO_L2P_T0L_N2_64` | `IO_L3P_T0L_N4_AD15P_64` (also I/O → why the LED constraint "worked") |
   | AP10/AP11 | PCIe refclk | `MGTREFCLK1N/P_225` (GTY quad 225) | GND / `D00_MOSI_0` |
   | M10/M11, H10/H11 | CAUI4 refclks | `MGTREFCLK0 _231 / _232` | GND |
   | BA35/BB35 … J19/J20 | DDR 100 MHz refclks | GC differential pairs (banks 41/66/47/71) | mixed GND/VCCO/IO |

   That is exactly the failure we saw: with the part set to flga2104, Vivado could not place
   `pin_sys_clk_n` on a VCCO ball or `pin_reset_n` on GND, dropped those LOCs, and the LED
   (an I/O in both packages) survived → `UCIO-1: 3 out of 4 ports unconstrained`.

## Consequences

* Build the pinned configs for **`xcvu9p-flgb2104-2-i`**. Huawei's `fx600.xdc` pins are correct as-is.
* The Huawei FX600 Developer Guide (EDOC1100053259, "Pin Constraint File Reference") has been
  taken offline by Huawei ("内容到期已下架"); `fpga-accel`'s `FX600/hw_platform/component/ICAP/README.md`
  quotes its sys_clk/reset example, identical to `fx600.xdc`.
* For the PCIe variant: the refclk sits on GTY quad 225 (`MGTREFCLK1_225`) in flgb2104.
* A bitstream built for flga2104 still *loads* on the card (JTAG checks the die IDCODE only), which is
  why the pin-free `scalar_selfclk` build worked regardless.
