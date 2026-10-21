# 28 — Imagen de diagnóstico construida en CI

## Run

```
39534664348   success
62 s (02:44:13 → 02:45:15)
```

Ya no recompila el kernel: descarga el artefacto `a34-fast` del run
`39480753110` y solo arma DTB + initramfs + boot image.

## Artefacto

```
ruby-diag-boot.img      134 217 728 B
  sha256 dbb4f66e81337408f018e36fb6e2799a631692e26f2b9d504be4e3cead454ce7

ruby-stock-base.dtb        179 275 B
  sha256 8b1bbb2c2fb70d2adb3562ff2f20f51b4bb1d87e9603173bbbbbda299fdbe111

ruby-diag-initramfs     2 302 501 B
```

## Validación

```
header v2, pagesize 2048
kernel   15 676 922 B  load 0x40080000  (idéntico al Image.gz del run)
ramdisk   2 302 501 B  load 0x51100000
dtb         179 275 B  load 0x47c80000
cmdline   bootopt=64S3,32N2,64N2 androidboot.tee_type=2
```

DTB:

```
symbols       445
dtbo targets   62
missing         0
ruby-dtb-probe  @48000000
pstore          @48090000 (0xe0000)
```

Initramfs:

```
11 módulos
aee_aed, clk-common, clk-mt6877, mt6359p-regulator,
mtk-pmic-wrap, mtk-spmi-pmic, mtk_wdt, pinctrl-mtk-v2,
pinctrl-mt6877, rtc-mt6397, spmi-mtk-mpu
```

## Diferencia con los tests anteriores

- Usa el **DTB stock de ruby**, no el DTB del A34.
- Conserva los 62 símbolos que necesita el **dtbo de la ROM**.
- Cmdline **stock**, sin overflow.
- Init con fallback `misc` 8:33 y pstore/pmsg.
- Sin storage A34, por el pánico de `sec_ext`.

## Estado

El dispositivo sigue en Android A, con `boot_b`/`misc` stock. **No se ha
flasheado esta imagen.**

## Próximo paso

Cuando se autorice:

1. `./scripts/mtk-slot.py set b --write`
2. copiar `ruby-diag-boot.img` a `/sdcard`
3. `dd` a `boot_b`, verificar sha256
4. reboot
5. esperar el retorno a Android y leer pstore/pmsg

El retorno esperado es por el init (si logra escribir el BCB) o por
`tries=1`; en ambos casos vuelve a A.
