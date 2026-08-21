#!/usr/bin/env bash
# Program the FPGA and run an ELF over JTAG. MUST run on the node that has the
# JTAG cable — submit with a node constraint or run in an interactive session:
#   dsub -q normal -o run.log donau/job_run.sh elf/wfi_slot_0.elf
set -euo pipefail
cd "$(dirname "$0")/.."
source donau/env.sh
ELF="${1:-elf/wfi_slot_0.elf}"; CFG="${2:-scalar}"
BIT="build/out_${CFG}/fx600_coralnpu_${CFG}.bit"
[ -f "$BIT" ] || { echo "ERROR: $BIT missing — build first"; exit 1; }
echo "== JTAG devices visible on $(hostname) =="
lsusb 2>/dev/null | grep -i -E "xilinx|ftdi|digilent" || echo "(no JTAG cable seen by lsusb — wrong node?)"
echo "== programming =="
vivado -mode batch -nojournal -source build/program.tcl -tclargs "$BIT"
echo "== running $ELF =="
python3 host/elf2jtag.py "$ELF" > /tmp/coralnpu_prog_$$.tcl
vivado -mode batch -nojournal -source host/jtag_run.tcl -tclargs /tmp/coralnpu_prog_$$.tcl 120
