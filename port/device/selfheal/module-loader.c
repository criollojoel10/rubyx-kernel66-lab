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
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define MODDIR "/lib/modules"
#define LOADFILE MODDIR "/modules.load"

static int kmsg = -1;
static int pmsg = -1;
static int wdt_pipe[2] = {-1, -1};

static void force_panic(void);

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

/*
 * pstore (ramoops) NO se borra entre arranques: los panics viejos llenan el
 * buffer de consola y el panic nuevo falla con ENOSPC ("pstore: backend
 * (ramoops) writing error (-28)"), asi que el arranque queda sin traza. Se
 * monta sysfs+pstore un momento, se borran los records y se desmonta todo
 * para no alterar el montaje que hara init despues.
 */
static void pstore_clear(void)
{
    DIR *d;
    struct dirent *e;

    (void)mkdir("/sys", 0755);
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0 && errno != EBUSY)
        return;
    (void)mkdir("/sys/fs/pstore", 0755);
    if (mount("pstore", "/sys/fs/pstore", "pstore", 0, NULL) != 0 &&
        errno != EBUSY) {
        (void)umount2("/sys", MNT_DETACH);
        return;
    }
    d = opendir("/sys/fs/pstore");
    if (d) {
        while ((e = readdir(d))) {
            char path[256];
            if (e->d_name[0] == '.')
                continue;
            snprintf(path, sizeof(path), "/sys/fs/pstore/%s", e->d_name);
            (void)unlink(path);
        }
        closedir(d);
    }
    (void)umount2("/sys/fs/pstore", MNT_DETACH);
    (void)umount2("/sys", MNT_DETACH);
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

/*
 * Registro persistente de arranque (diagnostico): un hijo que sobrevive al
 * execve de init y va volcando /dev/kmsg a la particion raw "oops" (sdc65,
 * 16 MB, vacia y sin uso en stock). Asi, aunque el kernel se cuelgue tras
 * arrancar init (display/HWC), la cola del log queda en eMMC y se lee desde
 * el slot A con `dd if=/dev/block/by-name/oops`. Se activa con MODDIR/.log-sink.
 */
#define SINK_MAX (12 * 1024 * 1024)

static int sink_open_partition(int partnum)
{
    char try[6][64];
    int n = 0, i;

    snprintf(try[n++], sizeof(try[0]), "/dev/sdc%d", partnum);
    snprintf(try[n++], sizeof(try[0]), "/dev/block/sdc%d", partnum);
    snprintf(try[n++], sizeof(try[0]), "/dev/mmcblk0p%d", partnum);
    snprintf(try[n++], sizeof(try[0]), "/dev/sda%d", partnum);
    snprintf(try[n++], sizeof(try[0]), "/dev/block/sda%d", partnum);
    try[n][0] = '\0';

    for (i = 0; i < n; i++) {
        int fd = open(try[i], O_WRONLY | O_CLOEXEC | O_SYNC);
        if (fd >= 0)
            return fd;
    }
    /* fallback: localiza la particion en sysfs y crea el nodo a mano (no hay
     * devtmpfs en este kernel, asi que /dev/sdcN no existe por si solo). */
    {
        DIR *d = opendir("/sys/class/block");
        struct dirent *e;
        if (d) {
            while ((e = readdir(d))) {
                char p[160], buf[40];
                FILE *f;
                unsigned maj = 0, min = 0;
                int part = -1, fd;
                if (e->d_name[0] == '.')
                    continue;
                snprintf(p, sizeof(p), "/sys/class/block/%s/partition",
                         e->d_name);
                f = fopen(p, "r");
                if (!f)
                    continue;
                if (fgets(buf, sizeof(buf), f))
                    part = atoi(buf);
                fclose(f);
                if (part != partnum)
                    continue;
                snprintf(p, sizeof(p), "/sys/class/block/%s/dev", e->d_name);
                f = fopen(p, "r");
                if (!f)
                    continue;
                if (fgets(buf, sizeof(buf), f) &&
                    sscanf(buf, "%u:%u", &maj, &min) == 2) {
                    char node[64];
                    snprintf(node, sizeof(node), "/dev/.rubysink.%d",
                             (int)getpid());
                    (void)mknod(node, S_IFBLK | 0600, makedev(maj, min));
                    fd = open(node, O_WRONLY | O_CLOEXEC | O_SYNC);
                    (void)unlink(node);
                    fclose(f);
                    if (fd >= 0) {
                        closedir(d);
                        return fd;
                    }
                    continue;
                }
                fclose(f);
            }
            closedir(d);
        }
    }
    return -1;
}

static void sink_loop(void)
{
    static const int parts[] = {65, 3, 1};
    int kfd, bfd = -1, part_used = -1, i, j;
    off_t off;
    char buf[8192];
    ssize_t r;

    (void)setsid();
    /* namespace de montaje propio: el init de Android remonta /sys y /dev y,
     * sin esto, desmonta el sysfs del que depende el fallback. */
    (void)unshare(CLONE_NEWNS);
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    kfd = open("/dev/kmsg", O_RDONLY | O_CLOEXEC);
    if (kfd < 0)
        _exit(1);

    /* El escaneo de particiones es asincrono: la particion puede no existir
     * aun en el momento del fork (UFS se carga mas tarde). Se reintenta hasta
     * ~30 s, remontando sysfs por si acaso y probando oops(65)/expdb(3)/misc(1). */
    for (i = 0; i < 150; i++) {
        (void)mkdir("/sys", 0755);
        (void)mount("sysfs", "/sys", "sysfs", 0, NULL);
        for (j = 0; j < (int)(sizeof(parts) / sizeof(parts[0])); j++) {
            bfd = sink_open_partition(parts[j]);
            if (bfd >= 0) {
                part_used = parts[j];
                break;
            }
        }
        if (bfd >= 0)
            break;
        (void)usleep(200000);
    }
    if (bfd < 0)
        _exit(2);

    {
        char hdr[64];
        int n = snprintf(hdr, sizeof(hdr),
                         "RUBYLOG v1 pid=%d part=%d\n", (int)getpid(),
                         part_used);
        (void)pwrite(bfd, hdr, (size_t)n, 0);
    }
    off = 4096;
    for (;;) {
        r = read(kfd, buf, sizeof(buf));
        if (r <= 0) {
            if (r < 0 && errno == EINTR)
                continue;
            (void)usleep(200000);
            continue;
        }
        if (off + r > SINK_MAX)
            off = 4096;
        (void)pwrite(bfd, buf, (size_t)r, off);
        off += r;
    }
}

/*
 * Watchdog de diagnostico: si el loader se queda colgado en un finit_module()
 * (llamada bloqueante), al cabo de N segundos fuerza un panic via sysrq "c".
 * El panic vuelca el ring buffer a ramoops (dmesg-ramoops-*) y ahi se ve el
 * ultimo "rubyload: [N] modulo.ko" = el modulo que colgo el arranque.
 * El loader mata a este hijo (SIGKILL) justo antes del execve de init, asi que
 * en un arranque sano el watchdog nunca dispara.
 */
static void watchdog_loop(void)
{
    int secs = 60;
    FILE *mf = fopen(MODDIR "/.wdt-secs", "r");
    if (mf) {
        if (fscanf(mf, "%d", &secs) == 1 && secs < 1)
            secs = 1;
        fclose(mf);
    }
    /* El padre escribe un byte en wdt_pipe[1] antes de cada finit_module: si
     * no llega ninguno en "secs" segundos, es que un modulo colgo la carga. */
    close(wdt_pipe[1]);
    for (;;) {
        struct pollfd pfd;
        char c;
        int pr;
        pfd.fd = wdt_pipe[0];
        pfd.events = POLLIN;
        pfd.revents = 0;
        pr = poll(&pfd, 1, secs * 1000);
        if (pr > 0) {
            while (read(wdt_pipe[0], &c, 1) > 0)
                ;
            continue;
        }
        if (pr < 0)     /* EINTR */
            continue;
        break;          /* timeout: colgado */
    }

    klog("rubyload: WATCHDOG %d s sin progreso, forzando panic\n", secs);
    force_panic();
}

/* Fuerza un panic via sysrq "c" para que el kernel vuelque el ring buffer a
 * ramoops (dmesg-ramoops-*). Si sysrq no esta disponible, reboot duro. */
static void force_panic(void)
{
    int fd;

    /* /proc lo desmonto log_unratelimit(); se vuelve a montar para poder
     * escribir en /proc/sysrq-trigger. */
    (void)mkdir("/proc", 0755);
    (void)mount("proc", "/proc", "proc", 0, NULL);

    fd = open("/proc/sys/kernel/sysrq", O_WRONLY);
    if (fd >= 0) {
        (void)write(fd, "1", 1);
        close(fd);
    }
    fd = open("/proc/sysrq-trigger", O_WRONLY);
    if (fd >= 0) {
        (void)write(fd, "c", 1);
        close(fd);
    }
    /* si sysrq no esta disponible, reboot duro como ultimo recurso. */
    reboot(RB_AUTOBOOT);
    _exit(0);
}

int main(void)
{
    FILE *f;
    char line[512];
    int total = 0, failed = 0, dry = 0;
    char fbuf[512] = "";
    pid_t wdt_pid = -1;

    /* .panic-now: beacon definitivo. Salir de PID 1 inmediatamente (ANTES de
     * cualquier mount/consola) fuerza "Attempted to kill init" -> ramoops.
     * Si este _exit no deja traza en dmesg-ramoops, el loader nunca llego a
     * ejecutarse en el slot B. */
    {
        struct stat _st;
        if (stat(MODDIR "/.panic-now", &_st) == 0)
            _exit(42);
    }

    log_open();
    klog("rubyload: v39 start (pid=%d)\n", (int)getpid());

    /* Watchdog ANTES de cualquier mount/pstore_clear: si algo de abajo
     * cuelga, el watchdog dispara force_panic y deja traza en ramoops. */
    if (pipe(wdt_pipe) != 0) {
        wdt_pipe[0] = wdt_pipe[1] = -1;
    }
    wdt_pid = fork();
    if (wdt_pid == 0)
        watchdog_loop();
    if (wdt_pid > 0)
        close(wdt_pipe[0]);
    klog("rubyload: watchdog forked (pid=%d)\n", (int)wdt_pid);

    log_unratelimit();
    klog("rubyload: ratelimit off\n");
    pstore_clear();
    klog("rubyload: pstore clear done\n");

    /* Hijo que graba /dev/kmsg en la particion oops desde YA: si un modulo
     * cuelga el arranque antes de llegar a execve, la traza queda en eMMC.
     * Se activa con MODDIR/.log-sink. */
    {
        struct stat st;
        if (stat(MODDIR "/.log-sink", &st) == 0) {
            pid_t pid = fork();
            if (pid == 0)
                sink_loop();
        }
    }

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
            /* kick al watchdog: si este modulo cuelga, el watchdog dispara. */
            if (wdt_pipe[1] >= 0)
                (void)write(wdt_pipe[1], "k", 1);
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

    /* .panic-secs=N: tras cargar todo y esperar N s (para que los probe
     * diferidos asienten y se vea el estado real de UFS/display), fuerza panic
     * y vuelca el ring buffer. Diagnostico de arranque completo. */
    {
        FILE *pf = fopen(MODDIR "/.panic-secs", "r");
        if (pf) {
            int psecs = 0, i;
            if (fscanf(pf, "%d", &psecs) == 1 && psecs > 0) {
                klog("rubyload: diagnostic panic en %d s\n", psecs);
                for (i = 0; i < psecs; i++)
                    sleep(1);
                force_panic();
            }
            fclose(pf);
        }
    }

    if (wdt_pid > 0)
        kill(wdt_pid, SIGKILL);

    char *argv[] = {"/init", NULL};
    char *envp[] = {"PATH=/sbin:/system/bin:/system/xbin", NULL};
    execve("/system/bin/init", argv, envp);
    klog("rubyload: execve de init fallo: %s\n", strerror(errno));
    for (;;)
        pause();
    return 0;
}
