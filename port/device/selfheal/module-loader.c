/*
 * Loader de modulos de primera etapa para ruby (diagnostico + arranque).
 *
 * El init de Android aborta el arranque cuando no puede cargar un modulo de
 * /lib/modules/modules.load, pero no dice el errno y el kernel no siempre deja
 * rastro. Este binario corre como /init, carga el mismo modules.load con
 * finit_module(), escribe cada errno en /dev/kmsg y luego deja el fichero vacio
 * (para que init no reintente) y ejecuta el init real.
 *
 * Compilar: aarch64-linux-gnu-gcc -static -O2 -o init module-loader.c
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define MODDIR "/lib/modules"
#define LOADFILE MODDIR "/modules.load"

static int kmsg = -1;

static void klog(const char *fmt, ...)
{
    char msg[448], out[512];
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);
    if (n <= 0 || kmsg < 0)
        return;
    /* <3> = KERN_ERR: pase lo que pase el loglevel, se registra. */
    n = snprintf(out, sizeof(out), "<3>%s", msg);
    if (n > 0)
        (void)write(kmsg, out, (size_t)((size_t)n < sizeof(out) ? (size_t)n
                                                                 : sizeof(out) - 1));
}

/*
 * En el ramdisk de primera etapa /dev puede estar vacio (devtmpfs lo monta el
 * init de Android), asi que /dev/kmsg no existe y los mensajes se perdian. Se
 * monta devtmpfs y, si aun asi no hay kmsg, se escribe en /dev/console, aunque
 * ahi conviene que el mensaje acabe en '\n'.
 */
static void log_open(void)
{
    kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (kmsg >= 0)
        return;
    (void)mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (kmsg >= 0)
        return;
    kmsg = open("/dev/console", O_WRONLY | O_CLOEXEC);
}

static int load_one(const char *name)
{
    char path[512];
    int fd, ret;
    snprintf(path, sizeof(path), MODDIR "/%s", name);
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        klog("rubyload: open %s failed: %d (%s)\n", path, errno,
             strerror(errno));
        return -1;
    }
    ret = (int)syscall(SYS_finit_module, fd, "", 0);
    if (ret != 0)
        klog("rubyload: finit_module %s failed: %d (%s)\n", name, errno,
             strerror(errno));
    close(fd);
    return ret;
}

int main(void)
{
    FILE *f;
    char line[512];
    int total = 0, failed = 0;

    log_open();
    klog("rubyload: start (root modules from %s)\n", LOADFILE);

    f = fopen(LOADFILE, "r");
    if (!f) {
        klog("rubyload: no %s (%s), sigo con init\n", LOADFILE,
             strerror(errno));
    } else {
        while (fgets(line, sizeof(line), f)) {
            char *p = line, *end;
            while (*p == ' ' || *p == '\t')
                p++;
            end = p + strlen(p);
            while (end > p && (end[-1] == '\n' || end[-1] == '\r' ||
                               end[-1] == ' '))
                *--end = 0;
            if (!*p || *p == '#')
                continue;
            total++;
            /* Si el kernel peta dentro de finit_module(), esta linea dice
             * cual era el modulo. */
            klog("rubyload: [%d] %s\n", total, p);
            if (load_one(p) != 0)
                failed++;
        }
        fclose(f);
    }
    klog("rubyload: %d modulos, %d fallos\n", total, failed);

    /* init aborta si el fichero existe y algo falla: lo vaciamos. */
    if (rename(LOADFILE, LOADFILE ".done") != 0)
        klog("rubyload: rename de modules.load fallo: %s\n", strerror(errno));
    f = fopen(LOADFILE, "w");
    if (f)
        fclose(f);
    else
        klog("rubyload: no pude crear modules.load vacio: %s\n",
             strerror(errno));

    char *argv[] = {"/init", NULL};
    char *envp[] = {"PATH=/sbin:/system/bin:/system/xbin", NULL};
    execve("/system/bin/init", argv, envp);
    klog("rubyload: execve de init fallo: %s\n", strerror(errno));
    for (;;)
        pause();
    return 0;
}
