# 18 — boot.img mínimo para consola

## Cierre reducido

El cierre de 22 módulos metía `mrdump` y `sec_debug` porque `iommu_debug`
depende de `mrdump`. Para consola no se necesita IOMMU.

Lista mínima (`console-min.list`), cierre real de **11 módulos**:

```
aee_aed.ko
clk-common.ko
clk-mt6877.ko
mt6359p-regulator.ko
mtk-pmic-wrap.ko
mtk-spmi-pmic.ko
mtk_wdt.ko
pinctrl-mtk-v2.ko
pinctrl-mt6877.ko
rtc-mt6397.ko
spmi-mtk-mpu.ko
```

Sin `mrdump`, sin `sec_debug`, sin IOMMU, sin MMC/UFS, sin display.

## Ramdisk

El `init` stock de ruby contiene:

```
/lib/modules
modules.load
insmod
```

Por eso no hace falta tocar `init.rc`: se copian los `.ko` y un
`modules.load` en orden topológico a `/lib/modules`, y `init` los carga.

```
ramdisk stock     20 651 368 B
ramdisk + 11 mod  22 937 634 B
```

## boot.img generado

```
kernel   38 054 400 B   A34 6.6.127 (run fast 39480753110)
ramdisk  22 937 634 B   stock ruby + 11 módulos
dtb         197 553 B   dts/ruby-minimal.dtb
header   v2, pagesize 2048
total    59 MB
```

Validado con `unpack_bootimg`; el ramdisk descomprime y contiene los 11
módulos y `modules.load`.

## Importante

- **No se ha flasheado nada.**
- El kernel es GKI del A34 con módulos del A34; no es todavía un kernel
  ruby completo.
- No incluye IOMMU/UFS: el arranque esperado es a consola/earlycon, no a
  Android.
- Rollback: `boot.img` stock de ruby (`/root/ruby-gki/dl/boot.img`,
  sha256 `c9d6ad0d...`).

## Prueba

Si se decide probar:

```
fastboot flash boot_a /tmp/ruby-boot-min.img
fastboot reboot
```

y capturar el log de consola/UART. Sin consola no se puede diagnosticar el
siguiente fallo.
