#!/usr/bin/env bash
# Simulate the real Coral NPU core with Vivado's xsim and dump full waveforms.
#   ./sim/run_sim.sh [elf] [cfg]     cfg = scalar (default) | rvv
# Produces sim/waves.vcd — open with:  vivado -mode gui  then File > Open Waveform
set -euo pipefail
cd "$(dirname "$0")/.."
ELF="${1:-elf/wfi_slot_0.elf}"; CFG="${2:-scalar}"
RTL="rtl/$CFG"; TOP=CoreMiniAxi; DEFS=""
[ "$CFG" = "rvv" ] && { TOP=RvvCoreMiniAxi; DEFS="-d VLEN_128 -d ZVE32F_ON -d USE_GENERIC"; }

command -v xvlog >/dev/null || { echo "load Vivado first: source /software/xilinx/Vivado/2024.2/settings64.sh"; exit 1; }

echo "== converting $ELF =="
ENTRY=$(python3 sim/elf2hex.py "$ELF" sim/prog.hex | sed 's/ENTRY=//')
echo "   entry=$ENTRY  words=$(wc -l < sim/prog.hex)"

echo "== compiling (xvlog) =="
rm -rf sim/xsim.dir sim/*.log sim/*.jou
xvlog -sv -i "$RTL" $DEFS $(ls "$RTL"/*.sv "$RTL"/*.v 2>/dev/null) sim/tb_coralnpu.sv --log sim/xvlog.log
echo "== elaborating (xelab) =="
xelab -debug typical -top tb_coralnpu -snapshot tb_sim --log sim/xelab.log
echo "== running (xsim) =="
xsim tb_sim -runall -testplusarg "PROG=sim/prog.hex" -testplusarg "ENTRY=${ENTRY}" --log sim/xsim.log
echo "== done: waveform at sim/waves.vcd =="
