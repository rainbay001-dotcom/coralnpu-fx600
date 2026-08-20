#!/usr/bin/env python3
"""elf2jtag.py — convert a Coral NPU ELF into Tcl data for jtag_run.tcl.

Usage: python3 host/elf2jtag.py elf/wfi_slot_0.elf > /tmp/prog.tcl
Emits: set entry 0x...; and a list of write bursts:
       lappend segs {addr_hex nwords {w0 w1 ...}}   (words little-endian, <=256 per burst)
Pure stdlib; no pyelftools needed.
"""
import struct, sys

def main(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 1:
        sys.exit("not a 32-bit ELF")
    (e_entry,) = struct.unpack_from("<I", data, 0x18)
    (e_phoff,) = struct.unpack_from("<I", data, 0x1C)
    (e_phentsize,) = struct.unpack_from("<H", data, 0x2A)
    (e_phnum,) = struct.unpack_from("<H", data, 0x2C)
    print(f"set entry 0x{e_entry:08x}")
    print("set segs {}")
    total = 0
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, _p_paddr, p_filesz, p_memsz = struct.unpack_from("<IIIIII", data, off)
        if p_type != 1 or p_memsz == 0:   # PT_LOAD only
            continue
        seg = bytearray(data[p_offset:p_offset + p_filesz])
        seg += b"\x00" * (p_memsz - p_filesz)
        if len(seg) % 4: seg += b"\x00" * (4 - len(seg) % 4)
        words = [struct.unpack_from("<I", seg, j)[0] for j in range(0, len(seg), 4)]
        total += len(words)
        for c in range(0, len(words), 256):
            chunk = words[c:c + 256]
            addr = p_vaddr + 4 * c
            wl = " ".join(f"{w:08x}" for w in chunk)
            print(f"lappend segs [list 0x{addr:08x} {len(chunk)} {{{wl}}}]")
    print(f"# total words: {total}")

if __name__ == "__main__":
    main(sys.argv[1])
