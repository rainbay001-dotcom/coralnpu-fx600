# First time on the FX600 machine — exact commands, in order

You never need the Vivado GUI. Every step is a shell command. Run them in order;
each step says what success looks like and what to save if it fails.

> Convention: `$` = normal user, `#` = root (use `sudo`).

---

## Phase 0 — look around (5 minutes, safe, changes nothing)

```bash
# 0.1 find Vivado and load it into your shell
ls /tools/Xilinx /opt/Xilinx 2>/dev/null           # one of these usually exists
source /tools/Xilinx/Vivado/*/settings64.sh 2>/dev/null || \
source /opt/Xilinx/Vivado/*/settings64.sh
which vivado && vivado -version                     # <-- SAVE THIS OUTPUT
```
Version guidance:
* **2020.x–2025.x** — proceed normally.
* **2018.x / 2019.x** (e.g. the 2018.3 that ships with Huawei's FX600 kit) — the
  scripts have compatibility shims, but the Coral NPU RTL is modern SystemVerilog
  and may not parse. **Run the 5-minute check in Phase 0.7 before building.**
* If several Vivado versions are installed, always prefer the newest:
  `ls -d /tools/Xilinx/Vivado/*/ /opt/Xilinx/Vivado/*/ 2>/dev/null`

```bash
# 0.2 confirm the license covers the VU9P and get the exact part name
vivado -mode tcl
```
At the `Vivado%` prompt type these two lines, then `exit`:
```tcl
get_parts -filter {DEVICE =~ xcvu9p*}
exit
```
SAVE the part list. If it's empty, the license doesn't cover VU9P — report it.

```bash
# 0.3 what does the card look like right now?
lspci | grep -i -E "xilinx|huawei|19e5|10ee"        # SAVE
# 0.4 is a JTAG cable visible?
lsusb | grep -i -E "xilinx|future|digilent"         # SAVE (FTDI/Xilinx cable)
# 0.5 basics present?
gcc --version | head -1; git --version; uname -r    # SAVE
```

```bash
# 0.6 get this repo
git clone https://github.com/rainbay001-dotcom/coralnpu-fx600.git
cd coralnpu-fx600
```
> **No internet on the cluster?** See [OFFLINE.md](OFFLINE.md): download the ZIP on
> a machine that has internet, move it through your shared folder, `unzip`, then
> `chmod +x donau/*.sh host/*.sh`.

```bash
# 0.7 FAST compatibility check (2-10 min) — does this Vivado understand the RTL?
cd ~/coralnpu-fx600
vivado -mode batch -source build/check_rtl.tcl -tclargs scalar 2>&1 | tee check_scalar.log
tail -30 check_scalar.log                          # <-- SAVE
```
Look for the last line:
* `CHECK_DONE ok` → this Vivado can build it. Go to Phase 1.
* `CHECK_DONE fail` → send me `check_scalar.log`; do not start a long build.

**Checkpoint: send back everything marked SAVE before building.**

---

## Phase 1 — build the scalar bitstream (30–60 min, unattended)

```bash
cd ~/coralnpu-fx600
nohup vivado -mode batch -source build/build.tcl -tclargs scalar > build_scalar.log 2>&1 &
# "scalar" builds the JTAG-only top (no PCIe) — correct for this machine.
tail -f build_scalar.log        # Ctrl-C stops watching, NOT the build
```
If Phase 0's part list showed a different name than `xcvu9p-flgb2104-2-i`,
pass it: `... -tclargs scalar xcvu9p-<your-package-and-grade>`.

**Success:** the log ends with
```
RESULT: cfg=scalar part=... WNS=<number> ns  bit=.../fx600_coralnpu_scalar.bit
BUILD_DONE
```
WNS ≥ 0 is perfect; small negative (> −1 ns) is usually still runnable — report it.

**Failure:** send the last 60 lines: `tail -60 build_scalar.log`.
The most likely first-run error is the PCIe location check — it names the fix
(edit `PCIE_BLK_LOCN` in `build/gen_ip.tcl`); send the message and wait.

---

## Phase 2 — program the FPGA over JTAG (2 minutes)

> This loads OUR design into the FPGA's SRAM. It is **volatile**: a power cycle
> restores Huawei's original image from flash. We never write flash, so nothing
> is permanent. If others use this card, warn them before this step.

```bash
# one-time: JTAG cable drivers (only if programming fails with "no hardware target")
# sudo $(dirname $(which vivado))/../data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers

vivado -mode batch -source build/program.tcl -tclargs build/out_scalar/fx600_coralnpu_scalar.bit
```
**Success:** `PROGRAMMED ... with ...` and no ERROR lines.

---

## Phase 3 — run Coral NPU over JTAG (1 minute; no PCIe, no root needed)

The card's PCIe is not connected, so everything — including running programs —
goes over the same JTAG cable. The runner is a Vivado script:

```bash
./host/jtag_run.sh elf/wfi_slot_0.elf
./host/jtag_run.sh elf/align_test.elf
./host/jtag_run.sh elf/finish_txn_before_halt.elf 60 0x00010000 8
```
**Success looks like:**
```
INFO: using hw_axi_1 on xcvu9p_0
bus check: wrote 0xDEADBEEF to START_PC, read 0xdeadbeef (OK)
loaded 8364 words in XXXX ms (spot-verified per burst)
entry point 0x00000000
core released
halted, status=0x1 (clean)
```
Exit code 0. `status=0x3` = program faulted (send output). Timeout = send output.
Watch the card: the activity LED blinks while running and goes solid on halt.

That's Coral NPU running on your FX600. 🎉

> Note: `jtag_run.sh` needs the same shell where you sourced `settings64.sh`
> (it calls vivado), and python3.

---

## Phase 4 (optional, later) — the vector core

```bash
nohup vivado -mode batch -source build/build.tcl -tclargs rvv > build_rvv.log 2>&1 &
```
~2–4 h build. Then Phase 2–3 with `out_rvv/fx600_coralnpu_rvv.bit`. Same ELFs run;
RVV-specific tests come after the scalar flow is proven.

## Phase 5 (someday) — PCIe
When the admin connects the card's PCIe slot, build `-tclargs scalar_pcie`
instead and use `host/setup_xdma.sh` + `host/pcie_rescan.sh` +
`host/coralnpu_run.c` (see README). Same core, faster host link.

## Getting back to normal
Power-cycle the machine (or just the card, if hot-swap) → Huawei's flash image
returns. Nothing we do here persists.
