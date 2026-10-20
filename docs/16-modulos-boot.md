# 16 — Módulos y empaquetado de boot

## Evidencia del ruby vivo

```
/vendor/lib/modules   82 archivos (.ko genéricos)
/proc/modules         1 módulo cargado: kheaders
```

El kernel stock de ruby **no carga módulos MTK**: los lleva built-in. Por eso
el modelo del A34 (978 `.ko`) no es directamente trasladable.

## Selección para el primer arranque

De los 978 módulos del A34 se seleccionaron 43 con
`scripts/select-boot-modules.py`:

- `clk-mt6877*`
- `pinctrl-mt6877`
- `mtk-pmic-wrap`, `mtk-spmi-pmic`, `mtk-spmi-tia-adc`, `spmi-mtk-mpu`
- `rtc-mt6397`, `mt6359p*`, `mt635x-auxadc`, `mt6577_auxadc`
- `nvmem-mt635x-efuse`
- `mtk-mmc*`, `phy-mtk-ufs`
- `mtk_iommu*`, `iommu_*`
- `mtk_wdt`
- `mtk-dvfsrc*`
- `mtk-mt6359`, `snd-soc-mt6359`, `mtk-pmic-keys`

Lista: `port/modules/boot-modules.list`.

## Boot header de ruby

`unpack_bootimg` del boot stock:

```
header version   2
pagesize         2048
kernel           21 082 776 B   load 0x40080000
ramdisk          20 651 368 B   load 0x51100000
dtb              179 139 B      load 0x47c80000
cmdline          bootopt=64S3,32N2,64N2 androidboot.tee_type=2
```

`scripts/repack-boot-ruby.sh` reempaqueta con esos offsets. Probado con el
kernel/ramdisk/DTB stock: reproduce tamaños y cabecera.

## Flujo previsto

1. `Image` del build propio.
2. `dts/ruby-minimal.dtb`.
3. Ramdisk stock de ruby (o uno con módulos).
4. `repack-boot-ruby.sh` → `boot.img` de prueba.
5. Validar con `unpack_bootimg` antes de pensar en flashear.

No se flashea nada en esta fase.

## Bundle de módulos

`collect-a34-artifacts.sh` ahora copia los 43 `.ko` seleccionados +
`modules.dep/load/alias/softdep` y genera
`artifacts/a34-6.6.127/a34-boot-modules.tar.zst`.

El build en curso usa el colector anterior; el bundle aparecerá en el
siguiente run.
