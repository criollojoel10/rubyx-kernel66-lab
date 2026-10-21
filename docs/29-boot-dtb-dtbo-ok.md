# 29 — Boot válido con DTB stock + dtbo y 11 módulos

## Run de CI

```
39537866051   success
Artefacto ruby-diag-boot
```

Cambio clave: el DTB stock **solo** lleva `ruby-dtb-probe`; ya no se añade
`pstore@48090000` porque el bootloader ya reserva pstore. El nodo duplicado
parece haber causado el crash de LK en el intento anterior.

## Resultado del boot en B

pstore:

```
Linux version 6.6.127-android15-8-abogkiA346BXXSEEZB6-4k
Machine model: MT6877V/TTZA
OF: reserved mem: ... ruby-dtb-probe
RUBYDIAG PID1_START
RUBYDIAG PSTORE kmsg=3 pmsg=4
...
RUBYDIAG MODULES_END
RUBYDIAG WATCHDOG_ARMED timeout=60
RUBYDIAG BOOT_DIAG_DONE returning_to_android
RUBYDIAG MISC_HARDCODE_NODE 8:33
RUBYDIAG MISC_OPEN_FAIL errno=6
```

pmsg:

```
11 MODULE_OK
```

Módulos:

```
aee_aed, clk-common, clk-mt6877, mt6359p-regulator,
mtk-pmic-wrap, mtk-spmi-pmic, mtk_wdt, pinctrl-mtk-v2,
pinctrl-mt6877, rtc-mt6397, spmi-mtk-mpu
```

El watchdog de hardware se armó a 60 s y el init volvió a Android.

## DTB y dtbo

- DTB stock ruby: `179 207 B`.
- `__symbols__`: 445.
- Targets del dtbo: 62/62.
- `ruby-dtb-probe` presente.
- El dtbo de la ROM puede aplicarse porque los símbolos están intactos.

## Lo que sigue fallando

`MISC_HARDCODE_NODE 8:33` + `MISC_OPEN_FAIL errno=6`: el dispositivo de bloque
`misc` no existe en el initramfs porque no hay driver de storage. El retorno a
Android funciona por `tries=1`, no por el BCB.

## Artefacto

```
/tmp/ruby-diag-art3/ruby-diag-boot.img
sha256 b8b5b29fe0442d171438b62f861fbcdc37d097e3721950a941eec3fbd2c487d6
```

## Estado

```
boot_b stock   c9d6ad0d...  restaurado
misc stock     a1a43d22...  restaurado
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
/sdcard limpio
```

## Conclusión

El bring-up con el DTB correcto y el dtbo aplicable **funciona**:

- kernel 6.6.127 del A34;
- 11 módulos;
- pstore/pmsg;
- watchdog;
- retorno a Android.

La base para la siguiente fase es `dts/ruby-stock-base.dtb` sin pstore duplicado
y el initramfs de 11 módulos.
