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
#include <sys/sysmacros.h>
#include <unistd.h>

#define MODDIR "/lib/modules"
#define LOADFILE MODDIR "/modules.load"

static int kmsg = -1;
static int pmsg = -1;

static void klog(const char *fmt, ...)
{
    char msg[448], out[512];
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);
    if (n <= 0)
        return;
    if (n > (int)sizeof(msg) - 1)
        n = (int)sizeof(msg) - 1;
    /* pmsg sobrevive al panic: es la unica traza fiable si ramoops no graba. */
    if (pmsg >= 0)
        (void)write(pmsg, msg, (size_t)n);
    /* <3> = KERN_ERR: pase lo que pase el loglevel, se registra. */
    n = snprintf(out, sizeof(out), "<3>%s", msg);
    if (n <= 0)
        return;
    if (n > (int)sizeof(out) - 1)
        n = (int)sizeof(out) - 1;
    /* fd 1 es /dev/console (lo abre el kernel para init): canal que funciona
     * aunque no exista /dev ni devtmpfs. */
    (void)write(1, out, (size_t)n);
    if (kmsg >= 0)
        (void)write(kmsg, out, (size_t)n);
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
    pmsg = open("/dev/pmsg0", O_WRONLY | O_CLOEXEC);
    if (kmsg >= 0 && pmsg >= 0)
        return;
    /*
     * En el ramdisk de primera etapa no existe ni siquiera el directorio
     * /dev: mount() devolvia ENOENT y todo el log se perdia. Se crea y se
     * monta devtmpfs encima; si aun asi falla, se crea kmsg a mano
     * (char 1:11), que no necesita devtmpfs.
     */
    (void)mkdir("/dev", 0755);
    (void)mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    if (kmsg < 0)
        kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (kmsg < 0) {
        (void)mknod("/dev/kmsg", S_IFCHR | 0600, makedev(1, 11));
        kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    }
    if (pmsg < 0)
        pmsg = open("/dev/pmsg0", O_WRONLY | O_CLOEXEC);
    if (pmsg < 0) {
        /*
         * Sin devtmpfs no hay nodo, pero pstore-pmsg es un misc device: su
         * minor esta en /proc/misc. Se crea a mano (char 10:minor).
         */
        FILE *mf = fopen("/proc/misc", "r");
        if (mf) {
            char l[128], name[64];
            int minor;
            while (fgets(l, sizeof(l), mf)) {
                if (sscanf(l, "%d %63s", &minor, name) == 2 &&
                    !strcmp(name, "pmsg")) {
                    (void)mknod("/dev/pmsg0", S_IFCHR | 0600,
                                makedev(10, minor));
                    pmsg = open("/dev/pmsg0", O_WRONLY | O_CLOEXEC);
                    break;
                }
            }
            fclose(mf);
        }
    }
    if (kmsg < 0)
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

/*
 * printk recorta a ~10 lineas cada 5 s: con 77 modulos solo se veian los 8
 * primeros ("70 output lines suppressed"). Como somos PID 1 y /proc ya existe,
 * se desactiva el ratelimit antes de empezar la traza.
 */
static void log_unratelimit(void)
{
    /*
     * printk_devkmsg="on" es el unico knob que importa: las escrituras a
     * /dev/kmsg se limitan por fichero abierto (5 s / 10 lineas) en
     * devkmsg_write() y las descartadas NO dejan rastro. printk_ratelimit
     * solo afecta a quien llama __printk_ratelimit(), no al loader.
     */
    static const char *const files[] = {
        "/proc/sys/kernel/printk_devkmsg",
        "/proc/sys/kernel/printk_ratelimit",
        "/proc/sys/kernel/printk_ratelimit_burst",
    };
    static const char *const vals[] = { "on\n", "0\n", "100000\n" };
    int i;

    /* Sin /proc montado los sysctl no existen y la traza se recorta a ~10
     * lineas cada 5 s: con 77 modulos se pierde justo el motivo del fallo. */
    (void)mkdir("/proc", 0755);
    (void)mount("proc", "/proc", "proc", 0, "");
    for (i = 0; i < 3; i++) {
        int fd = open(files[i], O_WRONLY | O_CLOEXEC);
        if (fd >= 0) {
            (void)write(fd, vals[i], strlen(vals[i]));
            close(fd);
        }
    }
    /* /proc se desmonta: si queda montado, el first stage de Android aborta
     * (exit 127) antes de imprimir nada. Los valores de ratelimit son globales
     * del kernel y sobreviven al desmontaje. */
    (void)umount2("/proc", MNT_DETACH);
}

/* Cuenta entradas reales (sin . / ..) de /sys/class/block. */
static int count_block(void)
{
    DIR *d;
    struct dirent *de;
    int n = 0;

    d = opendir("/sys/class/block");
    if (!d)
        return -1;
    while ((de = readdir(d))) {
        if (de->d_name[0] == '.')
            continue;
        n++;
    }
    closedir(d);
    return n;
}

/*
 * Prueba de UFS sin canal de log. Activada por MODDIR/.probe-block.
 *
 * Si tras ~6 s no hay ningun device en /sys/class/block, el arranque se queda
 * colgado aqui para siempre. Esa espera es la senal: el telefono NO vuelve al
 * slot A y la sesion SSH nunca responde => el bloque no existe con estos
 * modulos. Si el bloque aparece, se sigue a init como siempre.
 */
static void probe_block(void)
{
    struct stat st;
    int i, n = -1;

    if (stat(MODDIR "/.probe-block", &st) != 0)
        return;

    (void)mount("sysfs", "/sys", "sysfs", 0, NULL);
    for (i = 0; i < 30; i++) {
        n = count_block();
        if (n > 0)
            break;
        (void)usleep(200000);
    }
    if (n < 0) {
        klog("rubyprobe: /sys/class/block no existe, sigo\n");
        return;
    }
    klog("rubyprobe: %d devices de bloque tras %d ms\n", n, i * 200);
    if (n == 0) {
        klog("rubyprobe: SIN bloque, cuelgo aqui (UFS no probado)\n");
        for (;;)
            pause();
    }
}

/*
 * Deja en el log, en una sola linea, lo que de verdad importa del arranque:
 * si el controlador UFS tiene driver enlazado y cuantos discos hay. Se monta
 * sysfs un momento y se desmonta para no alterar el montaje de init.
 */
static void report_reg(const char *want, char *out, size_t outlen)
{
    DIR *d = opendir("/sys/class/regulator");
    struct dirent *e;
    char path[256], name[64];
    FILE *f;

    out[0] = '\0';
    if (!d)
        return;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.')
            continue;
        snprintf(path, sizeof(path), "/sys/class/regulator/%s/name", e->d_name);
        f = fopen(path, "r");
        if (!f)
            continue;
        if (fgets(name, sizeof(name), f)) {
            name[strcspn(name, "\n")] = '\0';
            if (strcmp(name, want) == 0) {
                snprintf(out, outlen, "%s", e->d_name);
                fclose(f);
                break;
            }
        }
        fclose(f);
    }
    closedir(d);
}

static void report_storage(void)
{
    struct stat st;
    char vemc[32], vufs[32];
    int bound, n, i;

    (void)mkdir("/sys", 0755);
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0 &&
        errno != EBUSY) {
        klog("rubyprobe: no pude montar sysfs (%s)\n", strerror(errno));
        return;
    }
    /* Los reguladores del PMIC aparecen ~1 s despues que los modulos y UFS
     * se reintenta solo. Esperamos hasta 2 s a que exista el bloque. */
    for (i = 0; i < 10 && count_block() == 0; i++)
        (void)usleep(200000);
    report_reg("vemc", vemc, sizeof(vemc));
    report_reg("vufs", vufs, sizeof(vufs));
    bound = (stat("/sys/bus/platform/devices/11270000.ufshci/driver", &st) == 0);
    n = count_block();
    klog("rubyprobe: ufshci_driver=%s block_devs=%d vemc=%s vufs=%s\n",
         bound ? "si" : "no", n, vemc[0] ? vemc : "no",
         vufs[0] ? vufs : "no");
    (void)umount2("/sys", MNT_DETACH);
}

int main(void)
{
    FILE *f;
    char line[512];
    int total = 0, failed = 0, dry = 0;
    char fbuf[512] = "";

    log_open();
    log_unratelimit();
    klog("rubyload: start (root modules from %s)\n", LOADFILE);

    /* Si existe MODDIR/.dryrun se recorre la lista sin cargar nada: sirve
     * para saber si el que borra el log es el propio loader o un modulo. */
    {
        struct stat st;
        if (stat(MODDIR "/.dryrun", &st) == 0) {
            dry = 1;
            klog("rubyload: modo dry-run\n");
        }
    }

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
            if (dry)
                continue;
            if (load_one(p) != 0) {
                failed++;
                if (strlen(fbuf) < sizeof(fbuf) - 40)
                    strcat(fbuf, p);
                if (strlen(fbuf) < sizeof(fbuf) - 2)
                    strcat(fbuf, " ");
            }
        }
        fclose(f);
    }
    klog("rubyload: %d modulos, %d fallos\n", total, failed);
    if (failed)
        klog("rubyload: fallos: %s\n", fbuf);

    /* init aborta si el fichero existe y algo falla: lo vaciamos. */
    if (rename(LOADFILE, LOADFILE ".done") != 0)
        klog("rubyload: rename de modules.load fallo: %s\n", strerror(errno));
    f = fopen(LOADFILE, "w");
    if (f)
        fclose(f);
    else
        klog("rubyload: no pude crear modules.load vacio: %s\n",
             strerror(errno));

    report_storage();
    probe_block();

    char *argv[] = {"/init", NULL};
    char *envp[] = {"PATH=/sbin:/system/bin:/system/xbin", NULL};
    execve("/system/bin/init", argv, envp);
    klog("rubyload: execve de init fallo: %s\n", strerror(errno));
    for (;;)
        pause();
    return 0;
}
