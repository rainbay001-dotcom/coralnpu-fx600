#!/usr/bin/env bash
# One-time host setup for the FX600 running the Coral NPU bitstream:
# build + load the Xilinx XDMA driver, then verify the card enumerates.
# Run as root. Re-run after every reboot (or add xdma to /etc/modules-load.d).
set -euo pipefail

if [ ! -d dma_ip_drivers ]; then
  git clone --depth 1 https://github.com/Xilinx/dma_ip_drivers.git
fi
pushd dma_ip_drivers/XDMA/linux-kernel/xdma >/dev/null
make -j"$(nproc)"
insmod xdma.ko poll_mode=1 || modprobe xdma || true
popd >/dev/null

echo "--- PCIe device (expect Xilinx 10ee:9038) ---"
lspci -d 10ee: -vv | head -30 || true
echo "--- XDMA device nodes ---"
ls -la /dev/xdma* 2>/dev/null || echo "no /dev/xdma* yet — did the bitstream load and did you rescan? (see host/pcie_rescan.sh)"
