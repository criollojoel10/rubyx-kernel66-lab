# Referencias para el port de ruby a 6.6

Inventario de los arboles publicos que se pueden usar como referencia y que
aporta cada uno. Fecha de la comparacion: 2026-10-22.

## 1. RubyxLabs (el proyecto de ruby)

<https://github.com/RubyxLabs>

| repo | rama | contenido |
|---|---|---|
| `kernel_xiaomi_mt6877` | `lineage-23.2` | kernel **4.19.325** (el stock de ruby) |
| `device_xiaomi_rubyx` | `lineage-23.2` | device tree del ROM |
| `vendor_xiaomi_rubyx` | `lineage-23.2` | vendor blobs |
| `hardware_mediatek`, `vendor_mediatek_ims`, `device_mediatek_sepolicy_vndr` | lineage-23.x | comunes de MTK para el ROM |

**No hay 6.6**: el kernel que publican es el 4.19.325, el mismo que ya esta en
`sources/ruby-4.19`. Es la fuente de verdad para el hardware de ruby (panel
m16, FT3680, goodix, aw882xx, dtbo), pero no para la API de 6.6.

Lo que se sigue usando de aqui: el DTB/dtbo de ruby, los drivers del 4.19 que
se portan (panel, tactil, huella, altavoz) y el vendor para saber que
propiedades y servicios espera el ROM.

## 2. Volla Quintus (MT6877, GKI 6.6)

`HelloVolla` publica el **mismo SoC que ruby** sobre GKI:

| repo | rama | version |
|---|---|---|
| `android_kernel_volla_mt6877` | `volla-16.0` | **Linux 6.6.89** |
| `android_kernel_device_modules_volla_mt6877` | `volla-16.0` | device modules de MTK |
| `android_kernel_modules_volla_mt6877` | — | modulos |
| `android_kernel_volla_mt6877` | `volla-14`, `volla-15.0` | 4.19.191 / 4.19.325 |

Es el **unico arbol publico 6.6 sobre MT6877** ademas del A34, y viene de un
telefono que arranca. Lo que trae ya resuelto para 6.6:

- `drivers/gpu/drm/mediatek/mediatek_v2/` (display v2, la API que usa el DTB
  de ruby) — misma familia que la copia del A34.
- `sound/soc/mediatek/{common,mt6877}/`: la card MT6877 con el framework
  `mtk-sp-spk-amp` y soporte de amplificador **AW883XX** (`MTK_SPK_AWINIC_AW883XX`),
  ademas de rt5509/mt6660/rt5512/tfa98xx. Es la via "de fabricante" para el
  altavoz, frente al array estatico que inyecta nuestro `apply-card.sh`.
- `drivers/tee/teei/` (Microtrust, igual que ruby) con
  `obj-$(CONFIG_MICROTRUST_TEE_SUPPORT) += teei/` en el Makefile de device
  modules.
- `drivers/misc/mediatek/imgsensor/src/isp6s/` — el ISP de MT6877.
- Tactil: `focaltech_touch`, `goodix_core`, `GT9896S/GT9895`, `NT36672C_I2C`,
  etc.
- Su `sound/soc/mediatek/common/Makefile` usa
  `CONFIG_DEVICE_MODULES_SND_SOC_MEDIATEK` y `CONFIG_SND_SOC_MTK_SRAM`/
  `SMART_PHONE`: el audio se compila **en los device modules**, no en el GKI.

## 3. Samsung A34 (nuestra base, 6.6.127)

El arbol de `kernel_samsung_a34x` (UN1CA) + ACK 6.6.127. Aporta:

- 6.6.127 (mas nuevo que el 6.6.89 de Volla) y el soporte de SoC MT6877 del
  GKI de Samsung.
- Cargador mt6360, GNSS MTK completo, UFS/pinctrl/PMIC ya funcionando en ruby.
- **No** trae panel m16, FT3680, goodix_cap, la card MT6877 ni `mediatek_v2`
  (eran untracked del laboratorio): todo eso se porto a mano.
- Su GKI **no** compila `CONFIG_SND_SOC_MEDIATEK` (audio muerto en el GKI): el
  audio del stock sale entero de los device modules como `.ko`.

## Comparacion y decisiones

| pieza | RubyxLabs 4.19 | Volla 6.6.89 | A34 6.6.127 | lo que usamos |
|---|---|---|---|---|
| panel m16 42-0d-0a | si (API 4.19) | no (otro panel) | no | portado del 4.19 a `mediatek_v2` |
| tactil FT3680 | si | focaltech generico | no | portado del 4.19 (SPI3) |
| huella goodix_cap | si | goodix_core (touch) | no | portado del 4.19 (TA `0x8888c03f`) |
| altavoz aw882xx | si | framework spk-amp + AW883XX | no | driver del 4.19 + dai_link inyectado |
| card MT6877 | si (4.19) | **si (6.6)** | no | common+card de los device modules del A34 (misma familia que Volla) |
| display v2 | no (4.19 usa otra API) | si | si (device modules) | copia del A34 |
| TEE | TEEI 400 | TEEI (Microtrust) | TEEGRIS de Samsung | TEEI 400 del 4.19 copiado al GKI |
| GNSS | DLink v030 | MTK GNSS | MTK GNSS completo | el del A34, sin tocar |
| camara isp6s | si (4.19) | si (6.6) | si (6.6, sin 4 sensores) | pendiente: comparar `isp6s` de Volla |

Conclusiones:

1. Para **arrancar y validar** seguimos con A34 6.6.127: es la base que ya
   llega a `vold`/`keystore2` en ruby.
2. **Volla 6.6.89** es la referencia para todo lo que el A34 no trae y hemos
   portado a mano (card MT6877, display v2, TEEI): si un port falla en runtime,
   el codigo de Volla es el que ya corre en un MT6877 real con 6.6.
3. Para la **camara**, el `imgsensor/src/isp6s` de Volla es la comparacion
   directa: mismo ISP, misma generacion de kernel. Es el siguiente frente
   despues de que el build salga verde.
4. El audio del A34 se compila en el GKI (built-in) porque los
   `CONFIG_DEVICE_MODULES_*` no existen en su configuracion; Volla lo compila
   como device modules porque su config si los tiene. Las dos vias son validas;
   la nuestra evita tocar las listas de Kleaf (que ya rompieron el build varias
   veces).
