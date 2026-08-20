#!/usr/bin/env bash
# After (re)programming the FPGA over JTAG, re-enumerate PCIe WITHOUT rebooting.
# Removes the card's old identity (Huawei shell 19e5: or our XDMA 10ee:), rescans,
# reloads the xdma driver. Run as root.
set -euo pipefail
for VID in 10ee 19e5; do
  for d in $(lspci -Dd ${VID}: 2>/dev/null | awk '{print $1}'); do
    echo "removing $d (vendor $VID)"; echo 1 > /sys/bus/pci/devices/$d/remove
  done
done
sleep 1
echo 1 > /sys/bus/pci/rescan
sleep 2
rmmod xdma 2>/dev/null || true
XKO="$(dirname "$0")/dma_ip_drivers/XDMA/linux-kernel/xdma/xdma.ko"
{ [ -f "$XKO" ] && insmod "$XKO" poll_mode=1; } || modprobe xdma 2>/dev/null || true
echo "--- card after rescan ---"
lspci -d 10ee: -vv 2>/dev/null | grep -E "^[0-9a-f]|LnkSta:|Region 0" || echo "no Xilinx 10ee device — bitstream loaded? JTAG ok?"
ls -la /dev/xdma* 2>/dev/null || echo "no /dev/xdma* nodes — driver load failed? (dmesg | tail -20)"
