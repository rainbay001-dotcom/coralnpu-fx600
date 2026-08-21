#!/usr/bin/env python3
"""elf2hex.py — ELF -> "ADDR DATA" hex list for the testbench to write over AXI.
Usage: python3 sim/elf2hex.py elf/wfi_slot_0.elf sim/prog.hex
Prints the entry point so run_sim.sh can pass it to the TB.
"""
import struct, sys

def main(inp, outp):
    d = open(inp, "rb").read()
    if d[:4] != b"\x7fELF" or d[4] != 1:
        sys.exit("not a 32-bit ELF")
    e_entry, e_phoff = struct.unpack_from("<I", d, 0x18)[0], struct.unpack_from("<I", d, 0x1C)[0]
    e_phentsize, e_phnum = struct.unpack_from("<H", d, 0x2A)[0], struct.unpack_from("<H", d, 0x2C)[0]
    n = 0
    with open(outp, "w") as f:
        for i in range(e_phnum):
            o = e_phoff + i * e_phentsize
            p_type, p_off, p_vaddr, _pa, p_filesz, p_memsz = struct.unpack_from("<IIIIII", d, o)
            if p_type != 1 or p_memsz == 0:
                continue
            seg = bytearray(d[p_off:p_off + p_filesz]) + b"\x00" * (p_memsz - p_filesz)
            if len(seg) % 4:
                seg += b"\x00" * (4 - len(seg) % 4)
            for j in range(0, len(seg), 4):
                f.write("%08x %08x\n" % (p_vaddr + j, struct.unpack_from("<I", seg, j)[0]))
                n += 1
    print("ENTRY=%08x" % e_entry)
    print("WORDS=%d" % n, file=sys.stderr)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
