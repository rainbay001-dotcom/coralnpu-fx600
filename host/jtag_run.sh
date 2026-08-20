#!/usr/bin/env bash
# Convenience wrapper: ./host/jtag_run.sh elf/wfi_slot_0.elf [timeout] [dump_hexaddr dump_words]
set -euo pipefail
ELF=$1; shift || true
python3 "$(dirname "$0")/elf2jtag.py" "$ELF" > /tmp/coralnpu_prog.tcl
exec vivado -mode batch -nolog -nojournal -source "$(dirname "$0")/jtag_run.tcl" -tclargs /tmp/coralnpu_prog.tcl "$@"
