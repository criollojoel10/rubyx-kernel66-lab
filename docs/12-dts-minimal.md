# 12 — Fase 4: DTS mínimo de ruby

## Datos tomados del dispositivo vivo

Por SSH/Termux (`scripts/pull-device-live.sh`, solo lectura):

```
model        MT6877V/TTZA
compatible   mediatek,mt6877 / mediatek,MT6877
memory       0x40000000, 8 GiB (0x2_00000000)
cmdline      console=tty0 console=ttyS0,921600n8 ... nokaslr
             clk_ignore_unused pd_ignore_unused
rtc0         mt-rtc mt6359-rtc
```

El `bootargs` del FDT confirma:
`androidboot.boot_devices=...soc/11230000.mmc...soc/11270000.ufshci`,
panel `m16-42-0d-0a`, y `bootopt=64S3,32N2,64N2`.

## Construcción del DTS

`scripts/make-ruby-dts.py` parte de
`sources/a34x/kernel/kernel_device_modules-6.6/arch/arm64/boot/dts/mediatek/mt6877.dts`
y aplica solo:

1. `model = "Xiaomi ruby (minimal)"`.
2. `compatible = "xiaomi,ruby", "mediatek,mt6877"`.
3. Nodo `/memory@40000000` de 8 GiB.
4. `chosen/stdout-path = "/serial@11002000"`.
5. `bootargs` de consola:
   `console=ttyS0,921600n8 earlycon loglevel=8 ignore_loglevel nokaslr clk_ignore_unused pd_ignore_unused`.

No edita el árbol del A34. El resultado es `dts/ruby-minimal.dts` y se compila
con `cpp` + `dtc`.

## Resultado

```
dts/ruby-minimal.dts   256 KiB
dts/ruby-minimal.dtb   197 553 B
```

Compila con warnings de `reg_format`/`simple_bus_reg` heredados del DTS del
A34, pero sin errores.

## Diferencia contra el FDT vivo

| Conjunto | Compatibles |
|---|---:|
| Comunes | 436 |
| Solo en el DTS mínimo (A34/Samsung) | 151 |
| Solo en el FDT vivo (ruby) | 167 |

Los 167 solo-vivo incluyen lo que todavía falta:

- PMIC `mt6359-*` (el DTS mínimo usa `mt6359p-*` del A34);
- paneles `m16_36_02_0b`, `m16_42_0d_0a`, `m16_45_02_0c`;
- táctil `focaltech,3680-spi`, `goodix,9916r-spi`;
- fingerprint `goodix,goodix-fp`;
- carga `ln8000`, `bq25980`, `sc8551/8561`, `ruby*_charger`;
- háptica/audio `aw8697`, `aw882xx`;
- nodos Xiaomi (`xiaomi,simtray-status`, `ruby_charger`, etc.).

Los 151 solo-mínimo son nodos del A34/Samsung (`samsung,*`, `mt6359p`,
`rt5133`, `ps5169`, etc.) que hay que recortar o desactivar.

## Hallazgos

1. **PMIC distinto**: ruby reporta `mt6359-rtc`, el A34 usa `mt6359p-rtc`.
   Hay que decidir si ruby es MT6359 o MT6359P; el driver del A34 soporta
   `mt6359p`. No se debe asumir que los registros/reguladores son idénticos.
2. **UART**: el DTS mínimo usa `mediatek,mt6577-uart`, que es el compatible
   que el driver del A34 sí reconoce. El FDT vivo declara
   `mediatek,mt6877-uart` + fallback `mt6577-uart`; el fallback es suficiente.
3. **Almacenamiento**: los nodos `mt6877-mmc` y `mt8183-ufshci` son comunes.
4. **Memoria**: 8 GiB confirmados; hay variantes de 6/12 GiB que requerirán
   detección por bootloader o DTS separado.

## Próximo

1. Recortar del DTS los nodos Samsung/A34 que no existen en ruby.
2. Alinear PMIC/reguladores con `mt6359-*` (o justificar `mt6359p`).
3. Añadir los nodos ruby imprescindibles: UART, almacenamiento, watchdog,
   RTC, pinctrl y reserved-memory.
4. Compilar el kernel con este DTS (Fase 5) y arrancar a consola.
