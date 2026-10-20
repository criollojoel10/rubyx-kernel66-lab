# 10 — Hito 2: brecha real de drivers ruby vs A34

## Método

Se parte del FDT vivo de ruby (`dts/ruby-live.dts`, 603 `compatible`) y del
subconjunto MT6877 del A34 (27 DTS, 597). Los 171 `compatible` que solo
aparecen en ruby se clasificaron así:

1. `reserved-memory` si el nodo vive bajo `/reserved-memory`.
2. `driver-in-a34` si el string exacto aparece en un `.c` del A34.
3. `fallback-a34` si otro `compatible` del mismo nodo sí está en el A34.
4. `port-driver` si el string exacto aparece en un `.c` del árbol 4.19.
5. `fallback-ruby` si otro `compatible` del mismo nodo está en 4.19.
6. `dts-only` si no aparece en ningún driver.

Búsqueda sobre 8 020 `.c` del A34 y 6 202 `.c` de ruby 4.19
(`compatible`, `of_device_id`, `i2c_device_id`).

**Límite:** esto identifica presencia de string, no compatibilidad de API.
Un driver presente en 4.19 puede requerir cambios para 6.6.

## Resultado

| Categoría | Cantidad |
|---|---:|
| `reserved-memory` (solo DTS) | 33 |
| `driver-in-a34` (reutilizable) | 34 |
| `fallback-a34` (cubierto por compatible genérico) | 5 |
| `alias-a34` (mismo driver, variante `p`/guion) | 11 |
| `port-driver` (existe en 4.19, falta en A34) | 63 |
| `fallback-ruby` (cubierto por genérico de 4.19) | 10 |
| `dts-only` (sin driver identificado) | 15 |
| **Total** | **171** |

## Port-driver por subsistema

| Subsistema | Nº | Ejemplos / archivo 4.19 |
|---|---:|---|
| Carga y batería | 20 | `bq25980.c`, `ln8000.c`, `ln8410.c`, `max77932.c`, `mp2762.c`, `sc8551.c`, `sc8561.c`, `mtk_charger.c`, `pd_cp_manager.c` |
| Cámara / vídeo / térmica | 15 | `mtk_jpeg_core.c`, `mmdvfs_pmqos.c`, `mtk_ts_*.c`, `st21nfc.c`, `clkbuf` |
| Display MediaTek | 6 | `mtk_disp_aal.c`, `mtk_disp_color.c`, SMI LARB |
| PMIC MT6359 | 7 | `mt6359_gauge.c`, `mt6397-core.c`, `mt635x-auxadc.c`, RTC, efuse, accdet, lbat |
| Audio | 4 | `aw882xx.c`, `mtk-dsp-pcm.c`, `mtk-scp-ultra-pcm.c`, `mt6359-accdet.c` |
| APU / VPU | 4 | `mnoc_drv.c`, `reviser_drv.c`, `dummy_vpu_driver.c` |
| Paneles | 3 | `panel-m16-36-02-0b-dsc-vdo.c`, `panel-m16-42-0d-0a-dsc-vdo.c`, `panel-m16-45-02-0c-dsc-vdo.c` |
| Touch | 3 | `focaltech_core.c` (3680), `goodix_brl_spi.c` (9916r), `xiaomi_touch.c` |
| Fingerprint | 2 | `gf_spi_tee.c` (goodix), `fpc1022_tee.c` |
| Haptics | 1 | `aw8697_haptic/aw_haptic.c` |
| DVFS | 1 | `helio-dvfsrc` (incluye `opp-v6877.c`) |
| I2C | 1 | `i2c-mtk.c` (compatible `i2c_common`) |
| Backlight | 1 | `leds-mtk-pwm.c` |
| Otros | 2 | `mt67xx-rng.c`, `fan53870.c` |

Detalle completo en `inventories/classification/ruby-only.tsv`.

## DTS-only (16)

```
android,firmware
android,nebula-gz-log-v1
mediatek,blue / green / red / button-backlight / jogball-backlight / keyboard-backlight
mediatek,camera_main_three
mediatek,md1_sim1_hot_plug_eint-eint
mediatek,md1_sim2_hot_plug_eint-eint
mediatek,mt6877-apusys-midware
mediatek,mt6877-camera-power-controller
mediatek,mtk_sec_video_path_support
mediatek,mtk_svp_on_mtee_support
mediatek,usb_boost
```

Interpretación: nodos de firmware/Trusty, LEDs de placa, un sensor de cámara
(normalmente userspace), middleware APU, controlador de potencia de cámara y
`usb_boost`. No son 16 drivers completos a portar; varios se resuelven con DTS
o con un driver ya existente bajo otro `compatible`.

## Fallbacks que reducen el trabajo

`fallback-a34` (5): `mediatek,mt6877-uart` cae en `mt6577-uart`;
`mt6877-fdvt` en el driver FDVT; `mt6877-ion-*` en el IOMMU/LARB.

`alias-a34` (11) es el hallazgo importante: el A34 ya tiene el driver, pero con
la variante `mt6359p` o con guion en vez de guion bajo. Cubre
`mt6359-accdet/auxadc/efuse/lbat_service/rtc/gauge`, `smi_common`, `smi_larb`,
`snd_audio_dsp`, `snd_scp_ultra` y `usb_boost`. No requieren portar código:
requieren alias de `compatible` o ajuste del DTS.

Eso deja el PMIC de arranque cubierto por alias, no por código nuevo.

`fallback-ruby` (10): SMI/LARB de cámara/display y `mt6877-disp-ovl-2l`, que
tienen driver genérico en 4.19.

## Prioridad de port

### P0 — arranque y consola

- UART: cubierto por fallback `mt6577-uart`; verificar clocks/IRQ.
- PMIC MT6359: RTC, gauge, auxadc, efuse, accdet, lbat, misc, `mt-pmic`.
- I2C, SMI/LARB, DVFSRC, idle-state, RNG.
- Reservado: 33 nodos de `reserved-memory` se copian del DTS, no son código.

### P1 — almacenamiento, USB y carga

- UFS/eMMC (común), USB (`xmusb350`, `usb_boost`), charger framework.
- `ln8000`, `bq25980`, `sc8551`/`sc8561`, `max77932`, `mp2762`,
  `mtk_charger`, `pd_cp_manager`.
- Sin esto no hay batería ni apagado seguro.

### P2 — pantalla y táctil

- 3 paneles M16, backlight (`lcd-backlight`, `disp-pwm-leds`), OVL 2L.
- `focaltech 3680`, `goodix 9916r`, `xiaomi-touch`.

### P3 — audio y háptica

- `aw882xx`, `mt6359-accdet`, `snd_audio_dsp`, `snd_scp_ultra`, `aw8697`.

### P4 — cámara, vídeo, APU

- `jpgenc`, VPU, `apusys_mnoc/reviser`, power controller de cámara,
  térmicas, `mmdvfs_pmqos`, `qos-2.0`.

### P5 — fingerprint, NFC, sensores

- Goodix/FPC, ST21NFC, sensores Xiaomi (`CUSTOM_KERNEL_*`).

## Decisión pendiente: GKI+módulos o built-in

El A34 es GKI + módulos (`=m`) y no tiene `vendor_boot`; ruby tampoco tiene
`vendor_boot`, pero su kernel stock lleva los drivers MTK **built-in**.

Para el primer arranque hay dos rutas:

1. **GKI + módulos**: Image limpio + `.ko` MTK en `vendor/lib/modules`.
   Más fiel al A34, pero exige init/ramdisk que cargue módulos y resolver
   dependencias.
2. **Built-in**: pasar a `=y` los drivers MTK mínimos. Más simple para
   consola/almacenamiento, pero agranda el Image y mezcla el modelo GKI.

No se decide todavía. Primero hay que medir el Image y el DTB mínimo.

## Siguiente paso

1. Auditar API de los 63 port-drivers contra 6.6 (no solo presencia).
2. Crear `configs/ruby-6.6-minimal/` con el mínimo P0.
3. Escribir el DTS mínimo ruby 6.6 (CPU, GIC, timer, UART, PMIC, storage,
   watchdog, reserved-memory).
4. Solo después, decidir GKI+módulos vs built-in.
