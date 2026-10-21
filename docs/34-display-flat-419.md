# 34 — Corrección: el stock 6.6 usa el DRM flat 4.19, no `mediatek_v2`

## Evidencia

El agente externo verificó el `vmlinux` stock y el kallsyms:

```
drivers/gpu/drm/mediatek/mi_disp/mi_disp_*.c
drivers/gpu/drm/mediatek/mtk_dsi.c
drivers/gpu/drm/mediatek/mtk_disp_*.c
```

- **0** ocurrencias de `mediatek_v2` en el binario.
- `mtk_dsi.c` stock contiene funciones 4.19-only
  (`mtk_dsi_fps_change_index`, `mi_mtk_dsi_esd_*`,
  `mtk_drm_early_resume`, etc.).
- `CONFIG_MI_DISP=y`, `CONFIG_DRM_MEDIATEK=y`,
  `CONFIG_DRM_PANEL_M16_*` built-in.
- El release 6.6.127 es un **forward-port del árbol 4.19 de RubyxLabs**,
  no un BSP `mediatek_v2`.

No existe ningún árbol público 6.6 de ruby. Las ramas públicas de
`kernel_xiaomi_mt6877` son 4.19.325 (RubyxLabs, MiCode, DXRN, forks).

## Consecuencia

El plan “panel-only sobre `mediatek_v2`” **no da paridad con el stock**:
pierde `mi_disp`, FOD/HBM/DC/GIR, y cambia el modelo de DTS/panel.

Para “igual o mejor” hay dos rutas:

### Ruta A — paridad (recomendada si se quiere FOD/HBM)

Portar el **DRM flat 4.19 + `mi_disp`** a ACK 6.6.127:

- base: `sources/ruby-4.19/drivers/gpu/drm/mediatek`
- paneles: `panel-m16-*`
- APIs a adaptar: `drmP.h`, `drm_panel_init/add`, `get_modes`,
  `panel->connector`, `mtk_panel_ext`, `mtk_ddic_dsi_send_cmd`
- referencia 6.6: `xiaomi-klee-devs/android_kernel_device_modules-6.6`
  rama `bsp-klee-w-oss` (`58fccc778584`), que tiene `mi_disp` 6.6
  (variante `mediatek_v2`, pero sirve de API).

Coste: 2–4 semanas. Es la única ruta fiel al stock.

### Ruta B — rápida (fallback)

Usar `mediatek_v2` del A34/Volla y adaptar los paneles m16. Coste 2–4 días,
pero sin `mi_disp`/FOD/HBM y con DTS distinto. Sirve para llegar a Android,
no para paridad.

## Donantes 6.6 verificados

| Repo | Rama/commit | Versión | Aporte |
|---|---|---|---|
| `xiaomi-klee-devs/android_kernel_device_modules-6.6` | `bsp-klee-w-oss` `58fccc778584` | 6.6.142 | `mi_disp` 6.6, mt6877, API reference |
| `HelloVolla/android_kernel_device_modules_volla_mt6877` | `volla-16.0` `3ad2f860c86c` | 6.6 | `mediatek_v2`, `mt6877.dts`, touch, chargers |
| `realme-kernel-opensource/...vendor-source` | `master` `b28a334a4c87` | 6.6.30 | `mediatek_v2`, GPS/consys mt6877, touch Oplus, chargers |
| `UN1CA/kernel_samsung_a34x` | `sixteen-qpr2` `a20c85b2e9` | 6.6.143 | UFS vendor + `mediatek_v2` |
| `Fede2782/android_kernel_samsung_a34x` | `sep-17.5/stock` `012174bdb7` | 6.6.92 | UFS/DSI reference |

## GPS

En el stock 6.6 el GPS/consys es **built-in**:

```
CONFIG_MTK_COMBO_CHIP_CONSYS_6877=y
CONFIG_MTK_COMBO_GPS=y
CONFIG_MTK_GPS_SUPPORT=y
CONFIG_MTK_GPS_EMI=y
CONFIG_MTK_CONNFEM=y
```

Si el kernel propio no incluye `consys`/`gps`, el GPS muere en kernel. Si se
usa el stock y falla, es userspace/firmware (`mnld`, HAL, `conninfra.cfg`,
firmwares, `vendor.connsys.driver.ready`).

## Decisión

- **P0**: terminar UFS propio sin Samsung.
- **P1**: elegir explícitamente:
  - paridad → port flat `mi_disp` 4.19 a 6.6;
  - velocidad → `mediatek_v2` + paneles m16 adaptados.
- **P2**: core con namespaces/Droidspaces; incluir `DEVTMPFS`, `TMPFS_XATTR`,
  `MACVLAN`, `NF_TABLES`, cgroups y GPS/consys.

No se ha flasheado nada. Build UFS `39596232093` sigue en ejecución.
