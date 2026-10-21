// PID 1 de diagnóstico para ruby (MT6877).
// - registra etapas en /dev/kmsg y /dev/pmsg0 (pstore)
// - carga los módulos de /lib/modules/modules.load
// - tras un margen, deja el slot A activo y reinicia a Android
// - si algo falla, también intenta volver a A; nunca deja B como activo.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/watchdog.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <unistd.h>

#define TOKEN "RUBYDIAG"
#define MISC_OFF 2048
#define BCB_SIZE 32
#define BCB_MAGIC 0x42414342u

static int klog = -1;
static int pmsg = -1;

static void logmsg(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n <= 0) return;
    if (klog >= 0) dprintf(klog, "<3>" TOKEN " %s\n", buf);
    if (pmsg >= 0) dprintf(pmsg, TOKEN " %s\n", buf);
}

static int mknode(const char *path, mode_t mode, unsigned int maj, unsigned int min) {
    if (mknod(path, mode, makedev(maj, min)) == 0 || errno == EEXIST) return 0;
    return -1;
}

static unsigned int dev_major(const char *sysdev) {
    unsigned int a = 0, b = 0;
    FILE *f = fopen(sysdev, "r");
    if (!f) return 0;
    if (fscanf(f, "%u:%u", &a, &b) != 2) a = 0;
    fclose(f);
    return a;
}

static unsigned int dev_minor(const char *sysdev) {
    unsigned int a = 0, b = 0;
    FILE *f = fopen(sysdev, "r");
    if (!f) return 0;
    if (fscanf(f, "%u:%u", &a, &b) != 2) b = 0;
    fclose(f);
    return b;
}

static int make_chr(const char *name, const char *sysdev) {
    unsigned int maj = dev_major(sysdev), min = dev_minor(sysdev);
    if (!maj && !min) return -1;
    return mknode(name, S_IFCHR | 0600, maj, min);
}

static int cmdline_misc(char *out, size_t outsz) {
    FILE *f = fopen("/proc/cmdline", "r");
    if (!f) return -1;
    char line[2048];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return -1; }
    fclose(f);
    char *p = strstr(line, "ruby.misc=");
    if (!p) return -1;
    unsigned int maj = 0, min = 0;
    if (sscanf(p, "ruby.misc=%u:%u", &maj, &min) != 2) return -1;
    if (mknode("/dev/misc", S_IFBLK | 0600, maj, min) < 0) return -1;
    snprintf(out, outsz, "/dev/misc");
    return 0;
}

static int find_partition(const char *part, char *out, size_t outsz) {
    if (!strcmp(part, "misc") && access("/dev/block/by-name/misc", F_OK) == 0) {
        snprintf(out, outsz, "/dev/block/by-name/misc");
        return 0;
    }
    DIR *d = opendir("/sys/class/block");
    if (!d) {
        logmsg("SYSFS_BLOCK_OPENDIR_FAIL errno=%d", errno);
        return -1;
    }
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char uevent[512];
        snprintf(uevent, sizeof(uevent), "/sys/class/block/%s/uevent", e->d_name);
        FILE *f = fopen(uevent, "r");
        if (!f) continue;
        char line[256];
        int match = 0;
        while (fgets(line, sizeof(line), f)) {
            if (!strncmp(line, "PARTNAME=", 9) && !strcmp(line + 9, part)) {
                match = 1;
                break;
            }
        }
        fclose(f);
        if (!match) continue;
        char devf[512];
        snprintf(devf, sizeof(devf), "/sys/class/block/%s/dev", e->d_name);
        unsigned int maj = dev_major(devf), min = dev_minor(devf);
        if (!maj && !min) continue;
        closedir(d);
        if (mknode(out, S_IFBLK | 0600, maj, min) < 0) {
            logmsg("MISC_MKNOD_FAIL maj=%u min=%u errno=%d", maj, min, errno);
            return -1;
        }
        (void)outsz;
        return 0;
    }
    closedir(d);
    return -1;
}

static uint32_t crc32_le(const uint8_t *p, size_t n) {
    uint32_t crc = 0xffffffffu;
    for (size_t i = 0; i < n; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320u : 0);
    }
    return ~crc;
}

static int set_active_a(void) {
    char misc[64] = "/dev/misc";
    if (find_partition("misc", misc, sizeof(misc)) < 0) {
        if (cmdline_misc(misc, sizeof(misc)) < 0) {
            if (mknode("/dev/misc", S_IFBLK | 0600, 8, 33) == 0) {
                snprintf(misc, sizeof(misc), "/dev/misc");
                logmsg("MISC_HARDCODE_NODE 8:33");
            } else {
                logmsg("MISC_NODE_FAIL errno=%d", errno);
                return -1;
            }
        } else {
            logmsg("MISC_CMDLINE_NODE %s", misc);
        }
    }
    int fd = open(misc, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        logmsg("MISC_OPEN_FAIL errno=%d", errno);
        return -1;
    }
    uint8_t b[BCB_SIZE];
    if (pread(fd, b, sizeof(b), MISC_OFF) != (ssize_t)sizeof(b)) {
        logmsg("MISC_READ_FAIL errno=%d", errno);
        close(fd);
        return -1;
    }
    uint32_t magic;
    memcpy(&magic, b + 4, 4);
    uint32_t stored;
    memcpy(&stored, b + 28, 4);
    if (magic != BCB_MAGIC || stored != crc32_le(b, 28)) {
        logmsg("MISC_BCB_INVALID magic=%08x crc=%08x", magic, stored);
        close(fd);
        return -1;
    }
    memset(b, 0, sizeof(b));
    memcpy(b, "_a\0\0", 4);
    magic = BCB_MAGIC;
    memcpy(b + 4, &magic, 4);
    b[8] = 1;          // version
    b[9] = 2;          // two slots
    b[12] = 0xff;      // A: prio 15, tries 7, successful 1
    b[14] = 0x7e;      // B: prio 14, tries 7, successful 0
    uint32_t crc = crc32_le(b, 28);
    memcpy(b + 28, &crc, 4);
    if (pwrite(fd, b, sizeof(b), MISC_OFF) != (ssize_t)sizeof(b)) {
        logmsg("MISC_WRITE_FAIL errno=%d", errno);
        close(fd);
        return -1;
    }
    fsync(fd);
    close(fd);
    logmsg("RETURN_SLOT_A_OK");
    return 0;
}

static void load_modules(void) {
    logmsg("MODULES_BEGIN");
    FILE *f = fopen("/lib/modules/modules.load", "r");
    if (!f) {
        logmsg("MODULES_LIST_MISSING errno=%d", errno);
        return;
    }
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!line[0]) continue;
        logmsg("MODULE_BEGIN %s", line);
        char path[320];
        snprintf(path, sizeof(path), "/lib/modules/%s", line);
        int fd = open(path, O_RDONLY | O_CLOEXEC);
        if (fd < 0) {
            logmsg("MODULE_OPEN_FAIL %s errno=%d", line, errno);
            continue;
        }
        long rc = syscall(SYS_finit_module, fd, "", 0);
        int err = errno;
        close(fd);
        if (rc == 0) logmsg("MODULE_OK %s", line);
        else logmsg("MODULE_FAIL %s errno=%d", line, err);
    }
    fclose(f);
    logmsg("MODULES_END");
}

static void arm_hardware_watchdog(void) {
    int fd = open("/dev/watchdog", O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        make_chr("/dev/watchdog", "/sys/class/watchdog/watchdog0/dev");
        fd = open("/dev/watchdog", O_WRONLY | O_CLOEXEC);
    }
    if (fd < 0) {
        logmsg("WATCHDOG_UNAVAILABLE errno=%d", errno);
        return;
    }
    int timeout = 60;
    if (ioctl(fd, WDIOC_SETTIMEOUT, &timeout) == 0)
        logmsg("WATCHDOG_ARMED timeout=%d", timeout);
    else
        logmsg("WATCHDOG_IOCTL_FAIL errno=%d", errno);
    // Se mantiene abierto: si el kernel se cuelga, el hardware resetea.
}

static void finish(void) {
    logmsg("BOOT_DIAG_DONE returning_to_android");
    set_active_a();
    sync();
    reboot(RB_AUTOBOOT);
    for (;;) pause();
}

static void on_alarm(int sig) {
    (void)sig;
    logmsg("WATCHDOG_TIMEOUT returning_to_android");
    finish();
}

int main(void) {
    mkdir("/dev", 0755);
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    int mr = mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    logmsg("MOUNT_DEVTMPFS rc=%d errno=%d", mr, errno);
    mr = mount("proc", "/proc", "proc", 0, NULL);
    logmsg("MOUNT_PROC rc=%d errno=%d", mr, errno);
    mr = mount("sysfs", "/sys", "sysfs", 0, NULL);
    logmsg("MOUNT_SYSFS rc=%d errno=%d", mr, errno);

    mknode("/dev/console", S_IFCHR | 0600, 5, 1);
    mknode("/dev/null", S_IFCHR | 0666, 1, 3);
    mknode("/dev/kmsg", S_IFCHR | 0600, 1, 11);
    klog = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (make_chr("/dev/pmsg0", "/sys/class/pmsg/pmsg0/dev") == 0 ||
        make_chr("/dev/pmsg0", "/sys/devices/virtual/pmsg/pmsg0/dev") == 0)
        pmsg = open("/dev/pmsg0", O_WRONLY | O_CLOEXEC);

    logmsg("PID1_START");
    logmsg("PSTORE kmsg=%d pmsg=%d", klog, pmsg);
    signal(SIGALRM, on_alarm);
    alarm(90);

    load_modules();
    arm_hardware_watchdog();
    logmsg("MODULES_DONE");

    // Margen para que pstore/console drenen antes de volver.
    sleep(20);
    finish();
    return 0;
}
