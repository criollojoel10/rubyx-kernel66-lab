# Puerto del panel m16-36-02-0b a mediatek_v2 (6.6)

## Fuentes

- Ruby 4.19: `sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c` (2192 líneas, API `mi_disp`).
- Referencia 6.6: `sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c` (1129 líneas, API `mediatek_v2`).
- Tablas DCS extraídas: `port/display/m16-36-02-0b-init.inc`.

## Decisión

Se **reescribe** sobre el panel de referencia 6.6 (no un parche mecánico): el API
de panel cambió por completo entre `mi_disp` y `mediatek_v2`.

## Delimitación de API (4.19 → 6.6)

| Tema | 4.19 (ruby) | 6.6 (mediatek_v2) |
|---|---|---|
| headers | `drm/drmP.h`, `mtk_panel_ext.h` | `drm/drm_connector.h`, `drm/drm_device.h`, `mediatek_v2/mtk_panel_ext.h` |
| init de panel | `drm_panel_init(&ctx->panel)` | `mtk_panel_init(ctx)` + `mtk_panel_add(ctx)` (API `struct mtk_panel_ctx`) |
| modos | `get_modes(panel)` | `get_modes(panel, connector)` |
| params | `struct mtk_panel_ext_params` | `struct mtk_panel_params` |
| callbacks | `struct mtk_panel_ext_funcs` | `struct mtk_panel_funcs` |
| `ext_param_set` | `(panel, mode)` | `(panel, connector, mode)` |
| `mode_switch` | `(panel, cur, dst)` | `(panel, connector, cur, dst, stage)` |
| `ext_param_get` | `(panel, mode)` | `(panel, connector, ext_para, mode)` |
| DCS envío | `mtk_ddic_dsi_send_cmd()` (interno de mediatek_v2, no exportado) | `mipi_dsi_dcs_write_buffer()` / `mipi_dsi_generic_write()` |
| GPIO | `of_get_named_gpio_flags()` | `of_get_named_gpio()` |
| estado panel | `panel->drm`, `panel->connector` | `connector->dev->dev`, `connector` |

## Datos del panel m16 (a conservar)

```
FRAME_WIDTH  1080
FRAME_HEIGHT 2400
PHYSICAL_WIDTH  69552
PHYSICAL_HEIGHT 154560
DATA_RATE 831
DSC_ENABLE 1, DSC_VER 17, DSC_SLICE_MODE 1, DSC_DSC_CFG 34
DSC_BIT_PER_PIXEL 128, DSC_SLICE_HEIGHT 20, DSC_SLICE_WIDTH 540
DSC_CHUNK_SIZE 540, DSC_XMIT_DELAY 512, DSC_DEC_DELAY 526
DSC_SCALE_VALUE 32, DSC_RC_MODEL_SIZE 8192
MAX_BRIGHTNESS_CLONE 16383
rc_buf_thresh / range_min_qp / range_max_qp / range_bpg_ofs  (ver .inc)
```

Modos: 30/60/90/120 Hz (según `lcm_get_modes` de ruby).
Init DCS: `port/display/m16-36-02-0b-init.inc` (convertir a `lcm_dcs_write_seq_static()`).
Compatible del nodo: `m16_36_02_0b_dsc_vdo,lcm`.

## Fuera de alcance (fase posterior)

- AOD/doze con `mi_disp` (`CONFIG_MI_DISP_VDO_TO_CMD_AOD`, `CONFIG_MI_DISP_FOD_SYNC`, `CONFIG_MI_DISP_ESD_CHECK`).
- Dimming GIR/HBM propietario (`mi_dsi_panel_tigger_dimming_work`).
- `mi_disp_notifier` para touch.

## Validación

1. `port/display/apply.sh` copia el panel y añade Kconfig/Makefile.
2. Build en Actions: overlay `CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO=m`.
3. En el dispositivo: `dmesg | grep m16`, `/sys/class/drm`, panel en `/sys/kernel/debug/dri/0/state`.
