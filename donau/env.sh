#!/usr/bin/env bash
# Locate and load Vivado on whatever node this runs on. Sourced by the other
# scripts. Picks the NEWEST version found unless VIVADO_VER is set.
find_vivado() {
  if command -v vivado >/dev/null 2>&1 && [ -z "${VIVADO_VER:-}" ]; then return 0; fi
  local cands=()
  for base in /software/xilinx /software/Xilinx /opt/Xilinx /opt/xilinx /tools/Xilinx /tools/xilinx \
              /usr/local/Xilinx /usr/share/Xilinx "$HOME/Xilinx" /share/Xilinx /data/Xilinx \
              /app/Xilinx /apps/Xilinx /eda/Xilinx /cad/Xilinx; do
    for s in "$base"/Vivado/*/settings64.sh; do [ -f "$s" ] && cands+=("$s"); done
  done
  if [ ${#cands[@]} -eq 0 ]; then
    echo "ERROR: no Vivado settings64.sh found. Set VIVADO_SETTINGS=/path/to/settings64.sh" >&2
    return 1
  fi
  local pick
  if [ -n "${VIVADO_VER:-}" ]; then
    pick=$(printf '%s\n' "${cands[@]}" | grep "/$VIVADO_VER/" | head -1)
  else
    pick=$(printf '%s\n' "${cands[@]}" | sort -V | tail -1)   # newest
  fi
  echo "INFO: sourcing $pick"
  # shellcheck disable=SC1090
  source "$pick"
}
[ -n "${VIVADO_SETTINGS:-}" ] && source "$VIVADO_SETTINGS" || find_vivado
echo "INFO: host=$(hostname) vivado=$(command -v vivado)"
vivado -version | head -2
# Report every version installed, so we know whether a newer one is available.
VROOT=$(dirname "$(dirname "$(dirname "$(readlink -f "$(command -v vivado)")")")" 2>/dev/null)
if [ -d "$VROOT" ]; then
  echo "INFO: versions installed under $VROOT: $(ls -1 "$VROOT" 2>/dev/null | tr '\n' ' ')"
fi
