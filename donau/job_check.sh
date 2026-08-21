#!/usr/bin/env bash
# Fast RTL compatibility check (2-10 min). Submit with:
#   dsub -q normal -o check.log -e check.err donau/job_check.sh
# or run directly inside an interactive xterm on a compute node.
set -euo pipefail
cd "$(dirname "$0")/.."
source donau/env.sh
CFG="${1:-scalar}"
vivado -mode batch -nojournal -source build/check_rtl.tcl -tclargs "$CFG"
