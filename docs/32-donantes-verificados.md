# 32 — Donantes verificados y decisión de port

## Correcciones al inventario anterior

1. **UFS A34**: el driver no tiene una tabla mt6877; sigue siendo
   `mediatek,mt8183-ufshci`. Los quirks mt6877 (`disable-mcq`, `qos`,
   `ah8-legacy`, etc.) vienen del **DTS**. Aun así, el vendor UFS de A34
   interpreta más caps que el upstream del GKI.
2. **UFS upstream GKI**: solo implementa 2 de los 5 caps de Ruby
   (`disable-ah8`, `broken-vcc`); ignora `disable-mcq`, `qos` y
   `ah8-legacy`. El stock de Ruby tampoco usa el UFS upstream.
3. **Display**: A34 tiene `mediatek_v2` con `MMSYS_MT6877` y
   `mt6877_dsi_driver_data`, pero **el stock de Ruby no usa `mediatek_v2`**:
   usa `drivers/gpu/drm/mediatek/mi_disp/*` del árbol 4.19. A34 no es
   reemplazo directo del display de Ruby.
4. **Paneles/touch/chargers**: no están en A34 6.6; solo en Ruby 4.19
   (RubyxLabs, MiCode, DXRN, forks) y en algunos árboles de otros equipos.

## Tabla verificada

| Repo / rama | Commit | Kernel | UFS mt6877 | DRM mt6877 | m16 | Touch Ruby | Chargers |
|---|---|---|---:|---:|---:|---:|---:|
| UN1CA A34 `sixteen-qpr2` | `a20c85b2e9` | 6.6.143 | DTS+caps | v2 | — | — | — |
| Fede A34 `sep-17.5/stock` | `012174bdb7` | 6.6.92 | DTS+caps | v2 | — | — | — |
| RubyxLabs `lineage-23.2` | `d15fffb90a` | 4.19.325 | sí | sí | 3/3 | FT3680+GT9916r | 4/4 |
| MiCode `ruby-s-oss` | `914ba8403b` | 4.19.191 | sí | sí | 3/3 | FT3680+GT9916r | 4/4 |
| DXRN `moonwake` | `7377452605` | 4.19.325 | sí | sí | 3/3 | FT3680+GT9916r | 4/4 |
| DXRN `aeron_kernel` | `609b127e8c` | 4.19.325 | sí | sí | 3/3 | FT3680+GT9916r | 4/4 |
| Volla `volla-16.0` | `79b7919575` | 6.6.89 | no | no | — | — | — |
| Volla `volla-15.0` | `ecfbc24d04` | 4.19.325 | sí | sí | — | — | sc8551 |
| OnePlus Nord CE2 | `3c1e3d432d` | 4.19.191 | sí | sí | — | — | sc8551 |
| crDroid `16.0` | `da90936d57` | 4.19.325 | sí | sí | 3/3 | FT3680+GT9916r | 4/4 |
| pissarro-dev | `d74524629c` | 4.14.336 | no | sí | — | — | parcial |

No existe un árbol público 6.6 de Ruby. Todas las ramas públicas de
`kernel_xiaomi_mt6877` son 4.19.

## Decisión de arquitectura

### P0 — UFS

Usar el **vendor UFS de A34** (el que entiende los caps del DTS mt6877) y
desactivar la cadena Samsung:

```
CONFIG_DEVICE_MODULES_SCSI_UFS_MEDIATEK=m
CONFIG_DEVICE_MODULES_PHY_MTK_UFS=m
CONFIG_DEVICE_MODULES_MTK_IOMMU=m
# CONFIG_SEC_UFS_FEATURE is not set
# CONFIG_SCSI_UFS_MEDIATEK_DBG is not set
# CONFIG_MTK_BLOCK_IO_TRACER is not set
# CONFIG_SEC_DEBUG is not set
# CONFIG_SEC_ABC is not set
```

No usar el UFS upstream del GKI: le faltan 3 quirks de Ruby.

### P1 — Display

Dos opciones reales:

1. **Portar `mi_disp` de Ruby 4.19 a 6.6** (fiel al stock, más trabajo:
   ~38 archivos, `drmP.h`, `drm_panel_attach`, `mtk_panel_ext`).
2. **Usar `mediatek_v2` de A34** (ya tiene mt6877 y API 6.6) y reescribir
   los paneles `m16_*` contra su `mtk_panel_ext`.

Recomendación: **opción 2 como primer intento** por menor churn de API;
mantener la opción 1 como fallback si el comportamiento no coincide.
A34 sirve de plantilla 6.6, no de reemplazo directo.

### P1 — Touch y charger

- Touch: portar `focaltech_3680` y `goodix_9916r` **SPI** desde Ruby 4.19.
  A34 es I2C/Samsung `sec_input` y no sirve.
- Charger: portar `ln8000`, `bq25980`, `sc8551`, `sc8561`,
  `pd_cp_manager` desde Ruby 4.19. A34 no los tiene.
- Necesitan stubs de `hwid`, `charger_class` v1 y `mi_disp_notifier`.

### Droidspaces

Corrección: el GKI que tenemos **no trae** `PID_NS`, `IPC_NS`, `USER_NS`,
`SYSVIPC` ni `POSIX_MQUEUE`. Solo `NAMESPACES`, `UTS_NS`, `NET_NS`, `MEMCG`,
`CPUSETS`.

Por tanto, Droidspaces exige **recompilar el core** con esos símbolos y el
parche kABI. No es gratis con el binario stock/A34.

## Orden de trabajo

1. Terminar build UFS y verificar que `ufs-mediatek-mod.ko` no depende de
   `sec_ext`/`sec_debug`.
2. Probar storage en slot B → `/dev/block/by-name/misc` y Android init.
3. Display con `mediatek_v2` + paneles m16 adaptados.
4. Touch SPI y charger.
5. Core propio con namespaces + Droidspaces.
6. GPS/consys: validar DTBO/reguladores y logs antes de tocar driver.

## Build actual

```
39591728145
A34 + device_modules UFS sin Samsung
```

Sigue en ejecución; se espera ~35–45m. No se ha flasheado nada.
