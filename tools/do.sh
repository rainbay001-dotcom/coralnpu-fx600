#!/usr/bin/env bash
# One entry point for every task, so nothing long has to be typed.
#
#   bash tools/do.sh doctor          collect environment info (Vivado, parts, JTAG)
#   bash tools/do.sh jtag            scan for a JTAG cable / FPGA
#   bash tools/do.sh reports         pull utilization+timing out of the routed checkpoint
#   bash tools/do.sh build [cfg]     full build (default cfg: scalar_selfclk)
#   bash tools/do.sh watch           follow the newest build log
#   bash tools/do.sh sim [elf]       simulate + dump waveforms (no hardware needed)
#   bash tools/do.sh program [cfg]   load the bitstream over JTAG
#   bash tools/do.sh run [elf] [cfg] program + run an ELF on the core
#   bash tools/do.sh collect         copy all logs/reports to ~/Downloads for Windows
#
# Every task also tees its output to ~/Downloads/coralnpu-out/<task>.log so you can
# open it in Notepad on Windows and paste it into the issue.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT="$HOME/Downloads/coralnpu-out"; mkdir -p "$OUT"
TASK="${1:-help}"; shift || true

vivado_env() {
  command -v vivado >/dev/null 2>&1 && return 0
  for s in /software/xilinx/Vivado/*/settings64.sh /opt/Xilinx/Vivado/*/settings64.sh \
           /tools/Xilinx/Vivado/*/settings64.sh /usr/local/Xilinx/Vivado/*/settings64.sh; do
    [ -f "$s" ] && cands+=("$s")
  done
  [ "${#cands[@]:-0}" -eq 0 ] && { echo "ERROR: no Vivado found"; return 1; }
  local pick; pick=$(printf '%s\n' "${cands[@]}" | sort -V | tail -1)
  echo "INFO: sourcing $pick"; source "$pick"
}
declare -a cands=()
vivado_env || exit 1
echo "INFO: host=$(hostname) vivado=$(command -v vivado)"

case "$TASK" in
  doctor)
    { echo "=== host ==="; hostname; uname -r
      echo "=== vivado ==="; vivado -version | head -2
      echo "=== vivado versions installed ==="; ls -1 /software/xilinx/Vivado/ 2>/dev/null
      echo "=== parts + package pin probe ==="
      cat > /tmp/parts.tcl <<'EOF'
puts "VU9P_PARTS: [lsort [get_parts -filter {DEVICE =~ xcvu9p*}]]"
foreach p [lsort [get_parts -filter {DEVICE =~ xcvu9p*}]] {
  if {[catch {link_design -part $p -quiet}]} { continue }
  set a [get_package_pins -quiet AY23]; set b [get_package_pins -quiet AR26]
  puts "PKGCHK $p AY23=[expr {[llength $a] ? {yes} : {no}}] AR26=[expr {[llength $b] ? {yes} : {no}}]"
  close_design -quiet
}
exit
EOF
      vivado -mode batch -nolog -nojournal -source /tmp/parts.tcl 2>&1 | grep -E "VU9P_PARTS|PKGCHK"
      echo "=== jtag ==="; bash "$ROOT/tools/do.sh" jtag 2>&1 | tail -8
    } 2>&1 | tee "$OUT/doctor.log"
    echo; echo ">>> saved to $OUT/doctor.log  (open it on Windows and paste to the issue)"
    ;;

  jtag)
    cat > /tmp/scan.tcl <<'EOF'
if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }
if {[catch {connect_hw_server -allow_non_jtag} e]} { if {[catch {connect_hw_server}]} { puts "NO_HW_SERVER"; exit 1 } }
set t [get_hw_targets -quiet]
if {[llength $t] == 0} { puts "NO_JTAG_TARGET"; exit 1 }
puts "TARGETS: $t"
foreach x $t { current_hw_target $x; if {[catch {open_hw_target}]} { continue }
  foreach d [get_hw_devices] { puts "DEVICE: $d part=[get_property PART $d] idcode=[get_property IDCODE $d]" }
  close_hw_target }
exit 0
EOF
    vivado -mode batch -nolog -nojournal -source /tmp/scan.tcl 2>&1 | tee "$OUT/jtag.log" | tail -10
    ;;

  reports)
    CFG="${1:-scalar}"
    DCP=$(ls -t build/out_$CFG/prj/*.runs/impl_1/*postroute_physopt.dcp build/out_$CFG/prj/*.runs/impl_1/*routed.dcp 2>/dev/null | head -1)
    [ -z "$DCP" ] && { echo "no routed checkpoint under build/out_$CFG"; exit 1; }
    echo "using $DCP"
    mkdir -p build/out_$CFG/reports
    cat > /tmp/rep.tcl <<EOF
open_checkpoint $DCP
report_utilization -file $ROOT/build/out_$CFG/reports/util_impl.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $ROOT/build/out_$CFG/reports/util_hier_impl.rpt
report_timing_summary -delay_type max -max_paths 10 -file $ROOT/build/out_$CFG/reports/timing_impl.rpt
puts "WNS_RESULT: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] ns"
exit 0
EOF
    { vivado -mode batch -nolog -nojournal -source /tmp/rep.tcl 2>&1 | grep -E "WNS_RESULT|ERROR"
      echo "=== utilization ==="; grep -m1 -A9 "CLB LUTs" build/out_$CFG/reports/util_impl.rpt
      echo "=== timing ==="; grep -m1 -A5 "Design Timing Summary" build/out_$CFG/reports/timing_impl.rpt
      echo "=== hierarchy ==="; grep -m1 -A14 -E "^\\|[[:space:]]+Instance" build/out_$CFG/reports/util_hier_impl.rpt
    } 2>&1 | tee "$OUT/reports.log"
    echo; echo ">>> saved to $OUT/reports.log"
    ;;

  build)
    CFG="${1:-scalar_selfclk}"; PART="${2:-}"
    LOG="$ROOT/build_$CFG.log"
    echo "starting build cfg=$CFG part=${PART:-auto} -> $LOG"
    nohup vivado -mode batch -nojournal -source build/build.tcl -tclargs "$CFG" $PART > "$LOG" 2>&1 &
    echo "PID $!  — follow with: bash tools/do.sh watch"
    ;;

  watch)
    LOG=$(ls -t "$ROOT"/build_*.log 2>/dev/null | head -1)
    [ -z "$LOG" ] && { echo "no build log yet"; exit 1; }
    echo "following $LOG (Ctrl-C stops watching, not the build)"; tail -f "$LOG"
    ;;

  status)
    LOG=$(ls -t "$ROOT"/build_*.log 2>/dev/null | head -1)
    [ -z "$LOG" ] && { echo "no build log yet"; exit 1; }
    { echo "log: $LOG"; grep -E "RESULT:|BUILD_DONE|^ERROR|Phase|synth_design completed" "$LOG" | tail -15
      echo "--- last lines ---"; tail -5 "$LOG"; } 2>&1 | tee "$OUT/status.log"
    ;;

  sim)  bash sim/run_sim.sh "${1:-elf/wfi_slot_0.elf}" 2>&1 | tee "$OUT/sim.log" | tail -20 ;;

  program)
    CFG="${1:-scalar_selfclk}"; BIT="build/out_$CFG/fx600_coralnpu_$CFG.bit"
    [ -f "$BIT" ] || { echo "missing $BIT — build first"; exit 1; }
    vivado -mode batch -nolog -nojournal -source build/program.tcl -tclargs "$BIT" 2>&1 | tee "$OUT/program.log" | tail -10
    ;;

  run)
    ELF="${1:-elf/wfi_slot_0.elf}"
    python3 host/elf2jtag.py "$ELF" > /tmp/prog.tcl || exit 1
    vivado -mode batch -nolog -nojournal -source host/jtag_run.tcl -tclargs /tmp/prog.tcl 120 2>&1 | tee "$OUT/run.log" | tail -20
    ;;

  collect)
    cp -f "$ROOT"/build_*.log "$OUT/" 2>/dev/null
    cp -f "$ROOT"/build/out_*/reports/*.rpt "$OUT/" 2>/dev/null
    cp -f "$ROOT"/check.log "$OUT/" 2>/dev/null
    ls -la "$OUT"; echo ">>> everything is in $OUT — open on Windows, paste into the issue"
    ;;

  *) sed -n '2,14p' "$0" ;;
esac
