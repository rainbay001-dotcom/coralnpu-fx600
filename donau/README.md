# Running this on a DonauKit (Huawei scheduler) cluster

The login node is a thin container: no Vivado, no FPGA. Everything must run on a
compute node via `dsub`.

## Get a shell on a compute node (best for exploring + JTAG work)
```bash
dsub -q normal --x11 xterm          # a terminal ON the compute node
# then inside that window:
source donau/env.sh                 # finds and loads the newest Vivado
hostname; lspci | grep -i -E "19e5|10ee"; lsusb | grep -i -E "xilinx|ftdi"
```

## Submit the long build as a batch job
```bash
dsub -q normal -n 8 -o build.log -e build.err donau/job_build.sh scalar
djob                                 # or dstat/dqueue — check status
tail -f build.log
```

## Quick compatibility check first (always)
```bash
dsub -q normal -o check.log -e check.err donau/job_check.sh scalar
tail -30 check.log                   # want: CHECK_DONE ok
```

## Program + run (must land on the node with the JTAG cable)
```bash
dsub -q normal -o run.log donau/job_run.sh elf/wfi_slot_0.elf
```
If the FPGA/JTAG lives on one specific host, add your scheduler's node
constraint (ask the admin for the exact flag, e.g. `-m <hostname>` or
`-l host=<name>`), or do this step inside an interactive xterm on that node.

## Notes
* `donau/env.sh` picks the newest Vivado it can find; force one with
  `VIVADO_VER=2022.2` or `VIVADO_SETTINGS=/path/settings64.sh`.
* Vivado wants scratch space; if `$HOME` is small or read-only on compute nodes,
  run from a work filesystem and pass `-o/-e` paths there.
