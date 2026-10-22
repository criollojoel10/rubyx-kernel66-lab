# 91 — Base MTK 6.6 para MT6877: la pieza que faltaba (hallazgo 2026-10-22)

## Resumen

El bloqueo documentado en `ruby-gki/STATUS.md` era que el arbol MTK 6.6 de
ruby (`kernel/xiaomi/mt6877`, rama `lineage-24.0`) no es publico, y sin el
no se puede compilar un kernel que arranque en ruby (205 `CONFIG_MTK_*`,
DRM/DSI, PMIC, tactil, carga... todo built-in en el `Image` de 53 MB).

**Ese arbol si existe en publico**, con el mismo SoC (MT6877), el mismo
framework (GKI 6.6 + `kernel_device_modules`) y la misma generacion de
drivers MTK:

| Repo | Que es | Rama |
|---|---|---|
| `HelloVolla/android_kernel_volla_mt6877` | GKI 6.6.89 (`gki_defconfig`, `build.config.gki.aarch64`, `abi.bzl`) | `volla-16.0` |
| `HelloVolla/android_kernel_device_modules_volla_mt6877` | device modules MTK 6.6 para MT6877 | `volla-16.0` |

## Que nos da ese arbol (relevante para ruby)

Ya verificado por API en el arbol de device modules:

- **TEE**: `drivers/tee/teei/{400,510,515}` -> Microtrust TEEI, que es el TEE
  real de ruby (el que falta hoy para `keymaster`/FBE).
- **Display**: `drivers/gpu/drm/mediatek/mediatek_v2/` (la API `mediatek_v2`
  con `mtk_panel_ctx`) + `drivers/gpu/drm/panel/mtk_drm_panel_drv.c` y
  `cust_panel/cust_lcm_hal.c` (el panel m16 es un `cust_panel`).
- **Paneles de referencia DSC/VDO de Xiaomi**: `panel-n11a-42-02-0a-dsc-vdo.c`
  y `panel-l12a-42-02-0a-dsc-cmd.c` (mismo estilo que m16, 1080x2400).
- **Touch**: `drivers/input/touchscreen/focal_FT3519/` con
  `focaltech_spi_v2.c` -> transporte SPI de Focaltech en 6.6 (ruby usa
  Focaltech **FT3680** por SPI3; ver `port/touch/README.md`).
- **Carga**: `drivers/power/supply/` con la infraestructura MTK completa
  (`mtk_charger`, `mtk_pe4/5`, `mtk_gauge`, `charger_class`, `adapter_class`,
  `sc8551-charger.c`, `rt9465`, `ufcs`...).
- **DTS**: `arch/arm64/boot/dts/mediatek/mt6877.dts` y
  `k6877v1_64.dts` (placa de referencia MTK) con `panel1/2/3` bajo `&dsi0`,
  backlight, haptic, altavoz, NFC y huella.
- **GNSS, audio, camara, PMIC mt6359p**: tambien presentes.

Lo que **no** trae (hay que portarlo desde el 4.19 de ruby):

- Panel `m16_36_02_0b` (DCS + timings propios).
- Focaltech FT3680 (chip id y calibracion).
- Cargadores de Xiaomi: `mp2762`, `ln8410`, `sc8551`/`sc8561` (ya hay
  sc8551), `bq25980`, `xmusb350` (USB-PD), `bq28z610` (fuel gauge),
  `max77932`.
- Huella Goodix por SPI.

## DTB: ya resuelto

En `ruby-gki/work/` esta el **DTB 6.6 de ruby**:

```
work/dtb_boot/01_dtbdump_MT6877.dtb   # DTB base del boot.img 6.6
work/dtbo_parts/01_dtbdump_RUBY.dtb   # overlay de ruby (particion dtbo)
```

Es decir: no hay que portar el Device Tree. Se reutiliza el DTB base 6.6
tal cual y el `dtbo` de ruby se queda en su particion. El overlay ya esta
escrito en el formato MTK 6.6 (`panel1@0` con `pm-enable-gpios`,
`reset-gpios`, `vddi-gpios`, `mi,esd-err-irq-gpio`; `m16-touch@0` con
`compatible = "focaltech,3680-spi", "goodix,9916r-spi"`; `mp2762@5c`;
`aw882xx@34`; `aw869x_haptic@5a`; `goodix,goodix-fp`), y por eso casa con
el `k6877v1_64.dts` de MTK 6.6 (nombres de nodo `panel1/2/3`, `touch_panel`).

## Dos vias, dos papeles

| Via | Base | Para que |
|---|---|---|
| **A (GKI puro)** | ACK 6.6.127 del A34 (lo que ya compila) | validar el parche kABI, la config de Droidspaces y el empaquetado. Es un GKI limpio, sin drivers de plataforma: sirve de banco de pruebas, no de ruby. |
| **B (MTK mt6877)** | GKI 6.6.89 + device modules MTK 6.6 de MT6877 | **este es el kernel de ruby**: display, touch, carga, TEE, GNSS, camara y audio. |

La via B sustituye a la via A como camino de producto. La via A se queda
como banco de pruebas del kABI y de la config de Droidspaces.

## Lo que hay que anadir a la via B

1. `m16_36_02_0b` sobre `mediatek_v2` (DCS + timings del 4.19, plantilla
   `panel-n11a-42-02-0a-dsc-vdo.c`).
2. Focaltech FT3680 por SPI (chip id + `focaltech,3680-spi`).
3. Cargadores Xiaomi (mp2762, ln8410, sc8561, bq25980, xmusb350, bq28z610,
   max77932) y fuel gauge.
4. Huella Goodix por SPI.
5. Config de Droidspaces + parche kABI oficial sobre el GKI de MTK.
6. DTB: el extraido de ruby (sin cambios) y el `dtbo` original.

## Riesgo asumido

El arbol publico es 6.6.89 y el de ruby era 6.6.127; y el arbol publico es
de otro OEM (Volla), asi que habra diferencias de configuracion. El
kABI se recalcula con nuestro propio baseline (`scripts/check-kabi.py`).
Los modulos del vendor (78 `.ko` genericos) no se ven afectados: son GKI
puro.

## Correccion importante: el arbol del A34 YA es un mt6877

Al revisar el arbol que ya teniamos (`UN1CA/kernel_samsung_a34x`):

- El submodulo `kernel-6.6` es `kernel_samsung_mediatek_common`, es decir el
  **GKI de MTK 6.6.127** (misma generacion y subversion que el kernel de ruby).
- `kernel_device_modules-6.6` es el **arbol de device modules de MTK para
  MT6877** (el A34 5G es un Exynos 1380 = MT6877V), con `mt6877/mgk.enabled`,
  `drivers/tee/teei/{400,510,515}`, `mediatek_v2`, `mt6359p`, la infraestructura
  MTK de carga, focaltech, goodix, GT9xx, etc.

Es decir: la base del laboratorio **ya es la plataforma MTK 6.6 de MT6877**.
Por tanto no hay que cambiar de base; hay que **añadir los drivers que son
propios del board de ruby**:

| Falta en el arbol A34 (mt6877) | Origen del port |
|---|---|
| panel `m16_36_02_0b` (DSC VDO 1080x2400) | ruby's 4.19 `panel-m16-36-02-0b-dsc-vdo.c` + plantilla `panel-n11a-42-02-0a-dsc-vdo.c` (arbol MTK publico) |
| Focaltech FT3680 por SPI3 | ruby's 4.19 `focaltech_3680/focaltech_spi.c` + `focaltech_spi_v2.c` del arbol MTK publico |
| cargadores: `mp2762`, `ln8410`, `sc8561`, `bq25980`, `xmusb350` (USB-PD), `bq28z610` (gauge), `max77932` | ruby's 4.19 (`sources/ruby-4.19`) |
| huella Goodix por SPI | ruby's 4.19 |
| GNSS/consys | `vendor/mediatek/kernel_modules/connectivity/gps/*` (aun por localizar) |

El arbol publico de MTK 6.6 mt6877 (Volla) pasa a ser, sobre todo, la
**biblioteca de referencias 6.6 nativas** para esos ports (panel n11a DSC,
`focaltech_spi_v2.c`, `cust_panel`, TEEI 400 ya presente en A34).

## Decision

Se sigue con la base actual (GKI MTK 6.6.127 + device modules MTK mt6877)
y se atacan, en este orden, los drivers propios de ruby:

1. **TEEI 400** (ya esta; solo faltaba el flag del overlay y el path de
   TEEGRIS para geniezone) -> keymaster/FBE.
2. **Panel m16** -> pantalla.
3. **Focaltech FT3680 SPI** -> tactil.
4. **Cargadores** -> carga real.
5. **Droidspaces** (config + parche kABI) sobre el GKI que ya compila.
