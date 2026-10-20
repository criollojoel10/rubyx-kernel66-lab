# 23 — Resultado del segundo intento

## Cronología

```
23:30:26 UTC  inicio
23:30:29      boot_b diag2 escrito y verificado (55e5b815...)
23:30:30      slot B activo, tries=1
23:30:32      reboot
~23:31:35     Android A de vuelta
```

## Resultado del arranque en B

pmsg quedó completo (1 058 B):

```
RUBYDIAG PSTORE kmsg=3 pmsg=4
RUBYDIAG MODULES_BEGIN
RUBYDIAG MODULE_OK aee_aed.ko
RUBYDIAG MODULE_OK clk-common.ko
RUBYDIAG MODULE_OK clk-mt6877.ko
RUBYDIAG MODULE_OK mt6359p-regulator.ko
RUBYDIAG MODULE_OK mtk-pmic-wrap.ko
RUBYDIAG MODULE_OK mtk-spmi-pmic.ko
RUBYDIAG MODULE_OK mtk_wdt.ko
RUBYDIAG MODULE_OK pinctrl-mtk-v2.ko
RUBYDIAG MODULE_OK pinctrl-mt6877.ko
RUBYDIAG MODULE_OK rtc-mt6397.ko
RUBYDIAG MODULE_OK spmi-mtk-mpu.ko
RUBYDIAG MODULES_END
RUBYDIAG WATCHDOG_ARMED timeout=60
RUBYDIAG MODULES_DONE
RUBYDIAG BOOT_DIAG_DONE returning_to_android
RUBYDIAG MISC_CMDLINE_NODE /dev/misc
RUBYDIAG MISC_OPEN_FAIL errno=6
```

Es decir:

- los **11 módulos cargan**;
- `mtk_wdt` arma el watchdog de hardware a 60 s;
- pmsg funciona (`/sys/class/pmsg/pmsg0`);
- el console-ramoops perdió las últimas líneas de módulos, pero pmsg las tiene
  completas.

## Retorno a Android

`MISC_OPEN_FAIL errno=6` (ENXIO): el nodo `/dev/misc` existe, pero el
dispositivo de bloque no está registrado en el initramfs. Sin storage no se
puede escribir el BCB.

Aun así volvió Android A porque B tenía `tries=1`:

```
A: prio 15, tries 1, success 1
B: prio 0, tries 0, success 0
```

## Estado restaurado

```
boot_b stock   sha256 c9d6ad0d...
misc stock     sha256 a1a43d22...
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
```

Se borraron de `/sdcard` las copias temporales.

## Conclusión

El segundo intento confirma:

1. El kernel 6.6.127 del A34 arranca en ruby.
2. Los 11 módulos del cierre cargan correctamente.
3. El watchdog de hardware se arma.
4. pstore/pmsg recoge el log completo.
5. El retorno automático a Android funciona por fallback de slot.

Queda pendiente escribir el BCB desde el init. Para eso hay que cargar antes
los módulos de almacenamiento (UFS/MMC) o resolver el nodo `misc` de otra
forma. No es bloqueante: el fallback `tries=1` ya devuelve Android.

Siguiente fase: probar el DTB ruby propio y luego añadir almacenamiento/IOMMU
para que el init pueda escribir el slot A por sí mismo.
