// BCB MTK para Android: lee/escribe bootloader_control en misc@2048.
// Binario estático para /data/adb/ruby/bctool.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define OFF 2048
#define SZ 32
#define MAGIC 0x42414342u
#define MISC "/dev/block/by-name/misc"

static uint32_t crc32_le(const uint8_t *p, size_t n) {
    uint32_t c = 0xffffffffu;
    for (size_t i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ ((c & 1) ? 0xedb88320u : 0);
    }
    return ~c;
}

static int read_bcb(uint8_t *b) {
    int fd = open(MISC, O_RDONLY | O_CLOEXEC);
    if (fd < 0) { perror("open misc"); return -1; }
    ssize_t n = pread(fd, b, SZ, OFF);
    close(fd);
    if (n != SZ) { fprintf(stderr, "pread %zd\n", n); return -1; }
    return 0;
}

static void show(const uint8_t *b) {
    uint32_t magic, stored, calc;
    memcpy(&magic, b + 4, 4);
    memcpy(&stored, b + 28, 4);
    calc = crc32_le(b, 28);
    printf("suffix=%.4s ver=%u A={prio:%u tries:%u ok:%u} B={prio:%u tries:%u ok:%u} crc=0x%08x %s\n",
           b, b[8], b[12] & 0xf, (b[12] >> 4) & 7, (b[12] >> 7) & 1,
           b[14] & 0xf, (b[14] >> 4) & 7, (b[14] >> 7) & 1,
           stored, (magic == MAGIC && stored == calc) ? "OK" : "BAD");
}

static unsigned char slot_byte(unsigned prio, unsigned tries, unsigned ok) {
    return (prio & 0xf) | ((tries & 7) << 4) | ((ok & 1) << 7);
}

static int write_bcb(uint8_t *b) {
    int fd = open(MISC, O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open misc rw"); return -1; }
    ssize_t n = pwrite(fd, b, SZ, OFF);
    if (n != SZ) { fprintf(stderr, "pwrite %zd\n", n); close(fd); return -1; }
    fsync(fd);
    close(fd);

    uint8_t back[SZ];
    if (read_bcb(back) < 0) return -1;
    if (memcmp(back, b, SZ) != 0) {
        fprintf(stderr, "readback distinto\n");
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    uint8_t b[SZ];
    if (read_bcb(b) < 0) return 1;
    if (argc < 2 || !strcmp(argv[1], "status")) { show(b); return 0; }
    if (strcmp(argv[1], "set") || argc < 3) {
        fprintf(stderr, "uso: %s status | set a|b [--write]\n", argv[0]);
        return 2;
    }
    uint8_t n[SZ];
    memcpy(n, b, SZ);
    if (!strcmp(argv[2], "a")) {
        memcpy(n, "_a\0\0", 4);
        n[12] = slot_byte(15, 7, 1);
        n[14] = slot_byte(14, 7, 0);
    } else if (!strcmp(argv[2], "b")) {
        memcpy(n, "_b\0\0", 4);
        n[12] = slot_byte(14, 7, 1);
        n[14] = slot_byte(15, 1, 0);
    } else {
        fprintf(stderr, "slot inválido\n");
        return 2;
    }
    uint32_t c = crc32_le(n, 28);
    memcpy(n + 28, &c, 4);
    show(n);
    if (argc < 4 || strcmp(argv[3], "--write")) {
        puts("dry-run: no se escribió nada");
        return 0;
    }
    if (write_bcb(n) < 0) return 1;
    puts("escrito y verificado");
    return 0;
}
