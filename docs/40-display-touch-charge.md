# 40 — Display, touch y carga 6.6: ruta B

Fecha: 2026-10-21

## Decisión

Para P1 se usa **`mediatek_v2`** del BSP A34, no `mi_disp` de 4.19.

- `mi_disp` son ~7 160 LOC y engancha 35 puntos de `mtk_dsi.c`.
- `mediatek_v2` ya está en `kernel_device_modules-6.6` como
  `CONFIG_DRM_MEDIATEK_V2`.
- El panel de referencia 6.6 es
  `drivers/gpu/drm/panel/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c`.
- Los paneles m16 ruby están en
  `sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-*.c`.

## APIs que hay que adaptar

| Ruby 4.19 | A34 6.6 |
|---|---|
| `#include <drm/drmP.h>` | no existe; usar `drm_connector.h`/`drm_device.h` |
| `drm_panel_init(panel)` | `drm_panel_init(panel, dev, funcs, connector_type)` |
| `drm_panel_add()` devuelve `int` | devuelve `void` |
| `get_modes(panel)` | `get_modes(panel, connector)` |
| `ext_param_set(panel, mode)` | `ext_param_set(panel, connector, mode)` |
| `mi_dsi_panel_tigger_dimming_work()` | no existe en A34; stub/recorte |
| `mtk_ddic_dsi_send_cmd(msg, blocking)` | `(msg, int blocking, bool need_lock)` |

`mtk_panel_ext_create`, `find_panel_ext` y `mtk_disp_notifier_*` sí están
exportados por `mediatek_v2`. `mtk_ddic_dsi_send_cmd` **no** está exportado:
el panel debe compilarse dentro del mismo `.ko` que `mtk_debug.o`/`mtk_dsi.o`,
o se añade el export (esto último toca el core y es riesgo kABI).

## Orden de trabajo

1. Portar **un solo panel**: `panel-m16-36-02-0b-dsc-vdo.c`.
2. Añadir `CONFIG_DRM_PANEL_M16_36_02_0B` a Kconfig/Makefile del BSP.
3. DTS: nodo `dsi0` con `panel@0` y `mtk_panel_ext_create`.
4. Verificar `dmesg` de `mediatek-drm`, `mtk_dsi`, `panel-m16` y
   `/sys/class/drm`.
5. Repetir con los otros dos paneles.
6. Touch: `xiaomi_touch`, luego `focaltech_touch`/`GT9895` del A34.
7. Carga: framework `mtk_charger`/`charger_class` del A34; después
   `ln8000`, `bq25980`, `sc8551`, `sc8561`; `pd_cp_manager` al final.

## Touch y carga

Touch:

```
xiaomi_touch.c
focaltech_touch/ (A34 ya lo trae)
GT9895/ (goodix_brl_spi.c)
```

Carga:

```
A34: drivers/power/supply/charger_class.c, mtk_charger.c, mt6360*, mt6362*, mt6375/79
Ruby: ln/ln8000.c, ti/bq25980.c, southchip/sc8551.c, sc8561.c, xiaomi/pd_cp_manager.c, misc/hwid/hwid.c
```

`linux/hwid.h` y `mt-plat/v1/charger_class.h` no existen en A34; hay que
portar `hwid.c` y cambiar el include al `charger_class.h` local del BSP.

## Verificación sin flashear

- `dmesg | grep -Ei 'mediatek-drm|mtk_dsi|panel-m16|drm'`
- `ls /sys/class/drm` y `/sys/kernel/debug/dri`
- `getevent -l` para touch
- `ls /sys/class/power_supply` para `mtk_charger`, `ln8000`, `battery`, `usb`

## Riesgo

Todo lo nuevo va como `.ko` de device_modules. No mover paneles/touch/chargers
al core GKI: `mtk_ddic_dsi_send_cmd` no está exportado y el kABI no debe
romperse.
