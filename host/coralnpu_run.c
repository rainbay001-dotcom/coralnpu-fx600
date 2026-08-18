/*
 * coralnpu_run — load and run a Coral NPU (CoreMiniAxi / RvvCoreMiniAxi) ELF
 * on the Huawei FX600 through the XDMA AXI-Lite window (/dev/xdma0_user).
 *
 * The AXI-Lite window maps 1:1 onto the core's address space:
 *   ITCM 0x00000..0x02000, DTCM 0x10000..0x18000, CSR base 0x30000
 *     CSR+0x0 : reset/clock-gate control (bit0)
 *     CSR+0x4 : start PC
 *     CSR+0x8 : status (bit0 = halted, bit1 = fault)
 *
 * Protocol is the repo's own (coralnpu_test_utils/core_mini_axi_interface.py):
 *   load_elf -> execute_from -> wait_for_halted.
 *
 * Build:  gcc -O2 -o coralnpu_run coralnpu_run.c
 * Usage:  sudo ./coralnpu_run <elf> [timeout_sec] [--dev /dev/xdma0_user]
 *                                  [--dump <hexaddr> <words>] [--verify]
 * Exit:   0 = halted clean, 2 = halted with FAULT, 3 = timeout, 1 = usage/IO error
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <elf.h>
#include <sys/mman.h>

#define CSR_BASE      0x30000u
#define CSR_RESET_CG  (CSR_BASE + 0x0u)
#define CSR_START_PC  (CSR_BASE + 0x4u)
#define CSR_STATUS    (CSR_BASE + 0x8u)
#define MAP_SIZE      (1u << 20)   /* 1 MiB: covers ITCM/DTCM/CSR for the default core */

static volatile uint32_t *g_bar = NULL;
static int g_verify = 0;

static inline void poke(uint32_t addr, uint32_t val) {
    g_bar[addr >> 2] = val;
    __sync_synchronize();
}
static inline uint32_t peek(uint32_t addr) {
    __sync_synchronize();
    return g_bar[addr >> 2];
}

static int load_elf(const char *path, uint32_t *entry) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); return -1; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(sz);
    if (!buf || fread(buf, 1, sz, f) != (size_t)sz) {
        fprintf(stderr, "elf read failed\n");
        fclose(f); free(buf); return -1;
    }
    fclose(f);

    Elf32_Ehdr *eh = (Elf32_Ehdr *)buf;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || eh->e_ident[EI_CLASS] != ELFCLASS32) {
        fprintf(stderr, "not a 32-bit ELF\n"); free(buf); return -1;
    }
    *entry = eh->e_entry;

    Elf32_Phdr *ph = (Elf32_Phdr *)(buf + eh->e_phoff);
    long words = 0, mismatches = 0;
    for (int i = 0; i < eh->e_phnum; i++) {
        if (ph[i].p_type != PT_LOAD || ph[i].p_memsz == 0) continue;
        uint32_t vaddr = ph[i].p_vaddr, fsz = ph[i].p_filesz, msz = ph[i].p_memsz;
        if (vaddr + msz > MAP_SIZE) {
            fprintf(stderr, "segment %d (0x%08x+0x%x) outside the 1 MiB window\n", i, vaddr, msz);
            free(buf); return -1;
        }
        printf("  segment %d: vaddr 0x%08x filesz 0x%x memsz 0x%x\n", i, vaddr, fsz, msz);
        const uint8_t *src = buf + ph[i].p_offset;
        for (uint32_t off = 0; off < msz; off += 4) {
            uint32_t w = 0;
            if (off < fsz) { uint32_t n = fsz - off < 4 ? fsz - off : 4; memcpy(&w, src + off, n); }
            poke(vaddr + off, w);
            words++;
            if (g_verify && peek(vaddr + off) != w) mismatches++;
        }
    }
    printf("  loaded %ld words%s\n", words,
           g_verify ? (mismatches ? " — READBACK MISMATCHES!" : ", readback verified") : "");
    free(buf);
    return mismatches ? -1 : 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <elf> [timeout_sec] [--dev /dev/xdma0_user] [--dump <hexaddr> <words>] [--verify]\n", argv[0]);
        return 1;
    }
    const char *elf_path = argv[1];
    const char *dev = "/dev/xdma0_user";
    int timeout_s = 60;
    uint64_t dump_addr = 0; int dump_words = 0;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--dev") && i + 1 < argc)        dev = argv[++i];
        else if (!strcmp(argv[i], "--dump") && i + 2 < argc)  { dump_addr = strtoull(argv[++i], NULL, 16); dump_words = atoi(argv[++i]); }
        else if (!strcmp(argv[i], "--verify"))                g_verify = 1;
        else if (argv[i][0] != '-')                           timeout_s = atoi(argv[i]);
    }

    int fd = open(dev, O_RDWR | O_SYNC);
    if (fd < 0) { perror(dev); fprintf(stderr, "is the XDMA driver loaded and the bitstream programmed?\n"); return 1; }
    g_bar = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (g_bar == MAP_FAILED) { perror("mmap"); return 1; }

    /* Sanity: with the core held in reset, status should read 0 and CSR writes must stick. */
    poke(CSR_RESET_CG, 1);            /* hold reset (bit0=1), un-gate clock */
    poke(CSR_START_PC, 0xDEADBEEF);
    uint32_t rb = peek(CSR_START_PC);
    printf("bus check: wrote 0xDEADBEEF to START_PC, read 0x%08x %s\n", rb, rb == 0xDEADBEEF ? "(OK)" : "(MISMATCH — bus/bridge problem)");
    if (rb != 0xDEADBEEF) return 1;

    printf("loading %s\n", elf_path);
    uint32_t entry = 0;
    if (load_elf(elf_path, &entry)) return 1;
    printf("entry point 0x%08x\n", entry);

    /* execute_from(): program start PC, release clock gate, release reset */
    poke(CSR_START_PC, entry);
    poke(CSR_RESET_CG, 1);
    poke(CSR_RESET_CG, 0);
    printf("core released\n");

    struct timespec t0, now; clock_gettime(CLOCK_MONOTONIC, &t0);
    uint32_t status = 0; long polls = 0;
    for (;;) {
        status = peek(CSR_STATUS); polls++;
        if (status & 1) break;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (now.tv_sec - t0.tv_sec > timeout_s) {
            fprintf(stderr, "TIMEOUT after %ds (status=0x%x, %ld polls)\n", timeout_s, status, polls);
            return 3;
        }
        struct timespec ts = {0, 200 * 1000}; nanosleep(&ts, NULL);
    }
    clock_gettime(CLOCK_MONOTONIC, &now);
    double ms = (now.tv_sec - t0.tv_sec) * 1e3 + (now.tv_nsec - t0.tv_nsec) / 1e6;
    int fault = (status >> 1) & 1;
    printf("halted after %.2f ms, status=0x%x (%s)\n", ms, status, fault ? "FAULT" : "clean");

    if (dump_words > 0) {
        printf("memory dump @ 0x%08lx:\n", (unsigned long)dump_addr);
        for (int i = 0; i < dump_words; i++)
            printf("  0x%08lx: 0x%08x\n", (unsigned long)(dump_addr + 4 * i), peek(dump_addr + 4 * i));
    }

    munmap((void *)g_bar, MAP_SIZE);
    close(fd);
    return fault ? 2 : 0;
}
