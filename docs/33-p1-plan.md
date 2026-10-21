# 33 — Plan P1: display, touch y carga

## Display: panel-only sobre `mediatek_v2`

No portar `mi_disp` en P1.

Datos medidos:

```
mi_disp 4.19       37 archivos, 7 160 LOC C
mediatek_v2 6.6   223 archivos, 258 352 LOC C
```

`mi_disp` no es un simple panel: engancha 35 puntos en `mtk_dsi.c` y 2 en
`mtk_drm_crtc.c`, duplica `struct mtk_dsi` y exige campos Xiaomi
(`mi_cfg`, `dsi_lock`, `display_type`, `panel_event`, AOD, FOD...). Portarlo
son 2–4 semanas.

Adaptar los paneles `m16_*` a `mediatek_v2` son **2–4 días**:

- quitar `<drm/drmP.h>`;
- `drm_panel_init()` con 4 argumentos;
- `drm_panel_add()` sin retorno `int`;
- `get_modes(panel, connector)`;
- `panel->drm` → `connector->dev`;
- `panel->connector` → `connector`;
- `ext_param_set`/`mode_switch` con `connector`;
- `of_get_named_gpio_flags` → `of_get_named_gpio`;
- `mtk_ddic_dsi_send_cmd` visible/exportado.

Se pierden HBM/FOD/DC/GIR/ESD Xiaomi; aceptable para llegar a Android.

## Touch

Orden:

1. `xiaomi_touch` (1 399 LOC).
2. `focaltech_3680` SPI (14 418 LOC).
3. `goodix_9916r` SPI (11 695 LOC), reutilizando `GT9895/goodix_brl_spi.c`.

Shim de `mi_disp_notifier` (~20 líneas) sobre `mtk_disp_notifier_*`, que A34
ya exporta. Cambios 6.6: `proc_ops`, `pde_data()`, `class_create(name)`,
`ktime_get_real_ts64`, `of_get_named_gpio`.

## Carga

Orden:

1. Framework A34: `mtk_charger`, `MT6359P`, `MT6360` (ya `=m`).
2. `ln8000` + `hwid.c`.
3. Después: `sc8551`, `sc8561`, `bq25980`, `pd_cp_manager`.

Problemas:

- `linux/hwid.h` no existe en A34; portar `hwid.c` (236 LOC) es más seguro
  que stubear el SKU.
- `charger_class` v1: header de reenvío a `drivers/power/supply/`.
- Props `power_supply` Xiaomi no están en el enum de A34; hay que recortarlas
  o rebuild de vmlinux (rompe GKI).
- `pd_cp_manager` necesita votables `BBC_*` y `pmic_voter`; se difiere.

## Droidspaces: faltantes reales

Además de `PID_NS`, `IPC_NS`, `USER_NS`, `SYSVIPC`, `POSIX_MQUEUE`:

```
CONFIG_DEVTMPFS
CONFIG_TMPFS_XATTR
CONFIG_TMPFS_POSIX_ACL
CONFIG_MACVLAN
CONFIG_NF_TABLES
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
CONFIG_CGROUP_PIDS
CONFIG_CGROUP_DEVICE
CONFIG_CFS_BANDWIDTH
CONFIG_CHECKPOINT_RESTORE
```

El core stock solo tiene `NAMESPACES/UTS/NET/MEMCG/CPUSETS/FREEZER`.
Hay que reconstruir vmlinux; no se puede con `.ko`.

`SYSVIPC` añade `sysvsem` a `task_struct` (riesgo KMI). `IPC_NS` puede
satisfacerse con `POSIX_MQUEUE`; validar si Droidspaces exige SysV.

## Estado

Build `39596232093` sigue en ejecución (A34 + UFS sin Samsung, defconfigs
parcheados). El dispositivo sigue en Android A, sin flashear.
