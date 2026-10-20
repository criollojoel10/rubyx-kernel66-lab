# 22 — Resultado de la prueba en slot B

## Cronología

```
23:20:21 UTC  inicio del script
23:20:25      boot_b escrito y verificado (hash 1c557cd3...)
23:20:26      slot B marcado (tries=1), readback OK
23:20:28      reboot
~23:21:30     Android A de vuelta (uptime posterior)
```

El script se cortó por un reinicio del servidor de trabajo, pero el
dispositivo completó la prueba solo.

## Lo que arrancó

pstore (`console-ramoops-0`, 36 365 B) contiene:

```
Linux version 6.6.127-android15-8-abogkiA346BXXSEEZB6-4k
Kernel command line: ... androidboot.slot_suffix=_b ...
RUBYDIAG PID1_START
RUBYDIAG PSTORE kmsg=3 pmsg=-1
RUBYDIAG WATCHDOG_UNAVAILABLE errno=2
RUBYDIAG MODULE_OK aee_aed.ko
RUBYDIAG MODULE_OK clk-common.ko
RUBYDIAG MODULE_OK clk-mt6877.ko
RUBYDIAG MODULE_OK mt6359p-regulator.ko
RUBYDIAG MODULE_OK mtk-pmic-wrap.ko
RUBYDIAG MODULE_OK mtk-spmi-pmic.ko
RUBYDIAG MODULE_OK mtk_wdt.ko
RUBYDIAG BOOT_DIAG_DONE returning_to_android
RUBYDIAG MISC_NODE_FAIL errno=2
reboot: Restarting system
```

También se vio:

```
clk_mt6877_top_probe init end
pwrap probe success
mtk-wdt ... Watchdog enabled (timeout=31 sec)
```

Es decir: **el kernel A34, clk, PMIC, pwrap y watchdog arrancaron en ruby**.

## Retorno a Android

El init no pudo abrir `misc` (`MISC_NODE_FAIL`), así que no escribió el slot A.
Aun así volvió Android porque el slot B estaba con **tries=1** y el bootloader
lo agotó, cayendo en A.

Estado tras el arranque:

```
suffix=_a
A: prio 15, tries 1, success 1
B: prio 0, tries 0, success 0
```

## Fallos a corregir

1. **pmsg**: el nodo correcto es `/sys/class/pmsg/pmsg0`, no
   `/sys/class/misc/pmsg0`. Por eso `pmsg=-1`.
2. **watchdog**: se armaba antes de cargar `mtk_wdt`; por eso
   `WATCHDOG_UNAVAILABLE`. Debe armarse después de los módulos.
3. **misc**: `/dev/block/by-name/misc` no existe en el initramfs y el lookup
   por sysfs falló. Se agregó fallback por cmdline `ruby.misc=8:33`.
4. **módulos 8–11**: no hay líneas de `pinctrl-mtk-v2`,
   `pinctrl-mt6877`, `rtc-mt6397` ni `spmi-mtk-mpu`. Se añadieron
   `MODULE_BEGIN`/`MODULES_END` para ver si el bucle se detiene o si fallan.

## Estado del dispositivo

Restaurado a baseline:

```
boot_b stock   sha256 c9d6ad0d...  (128 MiB)
misc stock     sha256 a1a43d22...
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
APatch root    uid=0 context=u:r:magisk:s0
```

Termux:

```
openssh 10.6p1-2
coreutils 9.12
util-linux 2.42.4
python3, ssh, scp, dd, sha256sum, base64
```

Se borraron de `/sdcard` las copias temporales (`ruby-diag.img`,
`boot_b-stock.img`, `misc-stock.img`).

## Nueva imagen preparada (no flasheada)

```
/tmp/ruby-diag2-stockdtb.img
128 MiB  sha256 55e5b8152f3e6b42aa54e94cfe7ddab35bf3eeb33dbf24cc6798c7e719fd6e22

init2     sha256 1900d4e9...
initramfs sha256 95e4ec61...
```

Incluye:

- pmsg en `/sys/class/pmsg/pmsg0`;
- watchdog armado después de cargar módulos;
- fallback `ruby.misc=8:33`;
- logs `MOUNT_*`, `MODULE_BEGIN`, `MODULES_END`;
- retorno A por BCB, no solo por fallback.

No se ha flasheado.
