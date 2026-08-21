#!/usr/bin/env bash
# Full bitstream build (30-60 min scalar, 2-4 h rvv). Submit with:
#   dsub -q normal -n 8 -o build.log -e build.err donau/job_build.sh scalar
set -euo pipefail
cd "$(dirname "$0")/.."
source donau/env.sh
CFG="${1:-scalar}"; PART="${2:-}"
if [ -n "$PART" ]; then
  vivado -mode batch -nojournal -source build/build.tcl -tclargs "$CFG" "$PART"
else
  vivado -mode batch -nojournal -source build/build.tcl -tclargs "$CFG"
fi
