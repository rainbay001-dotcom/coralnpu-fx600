# Coral NPU on the Huawei FX600 (Xilinx VU9P)

Runs Google's open-source [Coral NPU](https://github.com/google-coral/coralnpu) — the
scalar `CoreMiniAxi` core, and the full RVV vector core `RvvCoreMiniAxi` — on a
Huawei FX600 PCIe FPGA card, controlled from the host over PCIe (XDMA).

Everything needed is in this repo. The build machine needs **only Vivado** (no
Bazel, no Chisel — the RTL is pre-generated). The host machine needs Linux with
root, gcc, and a git clone of Xilinx's XDMA driver.

```
rtl/scalar/   CoreMiniAxi   — 99 files, generated from coralnpu @ 44141a10 (Chisel/firtool), macro-fixed for standalone Vivado
rtl/rvv/      RvvCoreMiniAxi — 201 files, same, includes the VeriSilicon RVV backend
board/        FX600 top (XDMA -> AXI-Lite CDC -> bridge -> core), constraints, the two glue modules
build/        build.tcl (one-shot RTL->bitstream), gen_ip.tcl (XDMA + AXI CDC IP)
host/         coralnpu_run.c (load ELF, run, poll), setup_xdma.sh, pcie_rescan.sh
elf/          three test programs from the coralnpu tree (built with its RISC-V toolchain)
```

## Architecture

```
 host CPU ──PCIe Gen3 x16──▶ XDMA IP (AXI-Lite master, BAR0, 1 MiB)
                                 │ 250 MHz
                           axi_clock_converter (async)
                                 │ core clock (62.5 MHz scalar / 25 MHz rvv, MMCM from 100 MHz sysclk)
                           axil_to_core_axi4  (32-bit lite -> single-beat 128-bit AXI4)
                                 │
                           CoreMiniAxi / RvvCoreMiniAxi  axi_slave
                                 │ axi_master
                           axi4_decerr_responder (stray accesses get DECERR, never hang)
```

Host BAR0 offset == core address (ITCM `0x0`, DTCM `0x10000`, CSR `0x30000`).
Boot protocol (from the coralnpu testbench): write ELF segments; write entry PC to
`0x30004`; write `1` then `0` to `0x30000`; poll `0x30008` (bit0 halted, bit1 fault).

## Build (Vivado machine)

```bash
git clone https://github.com/rainbay001-dotcom/coralnpu-fx600.git
cd coralnpu-fx600
# scalar core (start here — smaller, faster, known-good timing):
vivado -mode batch -source build/build.tcl -tclargs scalar
# vector core (second):
vivado -mode batch -source build/build.tcl -tclargs rvv
# if your part string differs (check `get_parts xcvu9p*` in Vivado Tcl):
vivado -mode batch -source build/build.tcl -tclargs scalar xcvu9p-flgb2104-2-i
```

Outputs land in `build/out_<cfg>/`: `fx600_coralnpu_<cfg>.bit`, `.mcs`, and
`reports/` (utilization, timing, DRC). The last log line prints `RESULT: ... WNS=...`.

Expected (from the same RTL on a VU47P): scalar ≈ 44k LUTs, closes 62.5 MHz easily;
rvv ≈ 405k LUTs (34% of the VU9P), 25 MHz target.

**Vivado version:** written for Vivado 2022.x–2025.x. See "Known version issues" below
if you are on something older.

## Program + run (host machine, root)

```bash
# 1. program the FPGA over JTAG (Vivado hardware manager or the CLI):
vivado -mode batch -source build/program.tcl -tclargs build/out_scalar/fx600_coralnpu_scalar.bit
# 2. re-enumerate PCIe without rebooting, load the XDMA driver:
sudo host/setup_xdma.sh      # first time (clones + builds the driver)
sudo host/pcie_rescan.sh     # after every re-program
# 3. build and run:
gcc -O2 -o host/coralnpu_run host/coralnpu_run.c
sudo host/coralnpu_run elf/wfi_slot_0.elf --verify
sudo host/coralnpu_run elf/align_test.elf --verify
sudo host/coralnpu_run elf/finish_txn_before_halt.elf --verify --dump 10000 8
```

Expected: `bus check ... (OK)`, `loaded N words, readback verified`,
`halted after X ms, status=0x1 (clean)`, exit code 0.

## What to send back (paste into an issue)

1. `build/out_<cfg>/reports/util_impl.rpt` (first ~40 lines) and `timing_impl.rpt` (first ~60 lines)
2. The `RESULT:` line from the Vivado log
3. `lspci -d 10ee: -vv` (a dozen lines)
4. Full stdout of the three `coralnpu_run` invocations
5. If anything fails: the last 50 lines of `vivado.log` / dmesg

## Known version issues

* **Vivado < 2020:** the RTL uses SystemVerilog features (packed structs, `unique case`,
  interface-free but modern syntax) and the fpnew FPU sources that older parsers reject.
  Please report the version before spending build time; a 2017–2019 workaround plan
  exists but is a bigger job.
* **PCIe block location:** `build/gen_ip.tcl` pins the XDMA IP to `X1Y2` / GTY quad 227.
  If Vivado complains that the reference-clock pins (AP10/AP11) don't match the quad,
  read `pcie_blk_locn` from Huawei's example project and adjust `PCIE_BLK_LOCN`.
* **`sys_rst_n`:** the top uses the board reset as the PCIe PERST proxy. If the link
  won't train, tie XDMA `sys_rst_n` to a free-running 1 (after IBUF) instead.

## Provenance

* Coral NPU RTL: Apache-2.0, google-coral/coralnpu @ `44141a10`, emitted with the repo's
  own Bazel targets; fpnew include fixes applied (see `rtl/*/README-fixes.md`).
* FX600 pins/config: from Huawei/fpga-accel `FX600/bare_metal` (Apache-2.0).
* Bridge, responder, top, scripts, host runner: this repo, Apache-2.0.
