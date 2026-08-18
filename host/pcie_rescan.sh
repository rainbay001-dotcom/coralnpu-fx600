#!/usr/bin/env bash
# After (re)programming the FPGA over JTAG, the PCIe endpoint has to be
# re-enumerated WITHOUT rebooting. Run as root:
#   1. remove the old device (if any), 2. rescan the bus, 3. reload xdma.
set -euo pipefail
for d in $(lspci -Dd 10ee: | awk '{print $1}'); do
  echo "removing $d"; echo 1 > /sys/bus/pci/devices/$d/remove
done
sleep 1
echo 1 > /sys/bus/pci/rescan
sleep 1
rmmod xdma 2>/dev/null || true
insmod "$(dirname "$0")/dma_ip_drivers/XDMA/linux-kernel/xdma/xdma.ko" poll_mode=1 || modprobe xdma
lspci -d 10ee: -vv | grep -E "^[0-9a-f]|LnkSta|Region 0" || echo "card not found after rescan"
ls -la /dev/xdma* 2>/dev/null || true
