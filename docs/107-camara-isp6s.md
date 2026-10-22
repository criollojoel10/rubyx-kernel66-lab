# Cámara: port del stack isp6s de 4.19 a 6.6

Estado: **inventario cerrado**, sin una sola línea de driver portada todavía.
Ruby es MT6877 con ISP6s (framework `imgsensor` por ioctl/proc, no V4L2).

## 1. Sensores reales de ruby

La nota antigua de "10 sensores" contaba variantes de driver, no sensores. Son
**5 sensores** y **10 variantes**. Fuente: `sources/ruby-4.19/drivers/misc/
mediatek/imgsensor/src/mt6853/camera_project/k6877v1_64_k419/` (10 directorios)
cruzado con `extracted/dts/ruby-dtbo.dts` (`camN_enable_sensor`).

| Slot | Sensor | Variantes (id) | i2c (tabla del driver) | Nodo del dtbo |
|---|---|---|---|---|
| cam0 principal | **s5khpx** | semco `0x1B70`, ofilm `0x1B71` | `0x20` | `camera_main@34` (i2c9) |
| cam0 alternativo | imx766 | sunny `0x0766`, ofilm `0x0767` | `0x34` (tabla `0x20`,`0x34`) | mismo nodo |
| cam1 frontal | **ov16a1q** | sunny `0x1640`, ofilm `0x1641` | `0x20` | `camera_sub@20` (i2c2) |
| cam2 | s5k4h7 | sunny `0x487B`, ofilm `0x487C` | `0x5A` | `camera_main_two@5a` (i2c2) |
| cam4 | **ov02b10** | aac `0x002B`, sunny `0x002C` | `0x78` (tabla `0x78`,`0x7A`) | `camera_sub_two@7a` (i2c4) |
| cam3 | — | `cam3_enable_sensor = [00]` | — | `camera_main_three@78` huérfano |

Principal = **s5khpx** (108 MP); imx766 es el fallback de la misma cámara.

## 2. Qué hay ya en 6.6

| Sensor | A34 6.6 (`isp6s`/`isp6s_mon`, `src/common/v1_1/`) | Volla 6.6.89 (`volla-16.0`) |
|---|---|---|
| imx766 | **sí** | sí |
| s5k4h7 | **sí**, pero como `s5k4h7front_mipi_raw` (`S5K4H7FRONT_SENSOR_ID`, 0x20) | solo `isp4_t/` + `s5k4h7front` |
| ov16a1q | **no** | **sí** (`common/v1_1/ov16a1q_mipi_raw`, id `0x561641+1`) |
| ov02b10 | **no** | **no** |
| s5khpx | **no** | **no** |

El A34 construye en realidad 6 sensores (`imx582, imx258, s5k4hayx, gc5035,
sr846d, hi1339`, proyecto `aaw_v34x`, `CONFIG_MTK_IMGSENSOR_ISP6S_MON=m`,
`CONFIG_MTK_IMGSENSOR` sin definir).

`sources/mtk-6.6-mt6877` (copia local de Volla) trae además el imgsensor
**ISP8/V4L2** (`vendor/mediatek/kernel_modules/mtkcam/imgsensor/{src-isp8,
src-v4l2,src_spm-isp8,inc/kd_imgsensor_define_v4l2.h}`): es otra API y no sirve
para isp6s.

## 3. De dónde portar lo que falta

- **s5khpx** — no hay driver 6.6 en ningún árbol alcanzable. Solo 4.19/5.10.
  Mejor base: `itswill00/android_kernel_xiaomi_tanzanite` (Linux **5.10.209**,
  `drivers/misc/mediatek/imgsensor/src/common/v1_1/s5khpx_sunny_main_mipi_raw/`),
  `.c` 2.771 líneas + `.h` 12.613, mismo `checksum_value = 0x47a75476` y mismos
  modos 4080×3060/3072 que el semco de ruby. Ruby aporta 4 variantes de
  ~21,5 k líneas (c+h) cada una.
- **ov02b10** — sin driver 6.6 de MTK. Solo 5.10
  (`MotorolaMobilityLLC/kernel-mtk`, `common/v1_1/{mot_vicky,mot_devonn}_ov02b10_mipi_raw`)
  y 4.14 OnePlus mt6893. Ruby: ~1,7 k líneas.
- **ov16a1q** — basta una variante nueva sobre el driver de Volla (~3,3 k líneas
  `.c`): su `OV16A1Q_SENSOR_ID` es `0x561641+1`, no `0x1640`/`0x1641`.

Delta de API 4.19→6.6 en isp6s `v1_1`: **pequeño**. El `ov16a1q` de Volla sigue
usando `iReadRegI2C/iWriteRegI2C/iReadRegI2CTiming` con las mismas firmas, y
cada sensor conserva su copia de `struct imgsensor_info_struct` /
`imgsensor_struct`. Cambios a hacer: incluir `kd_camera_feature.h` e
`imgsensor_i2c.h` en vez de declarar externs locales; `kal_uint*` sigue en
`kd_camera_typedef.h`; `imgsensor_sensor_init` y el probe no cambian.

## 4. Plomería de registro

- `imgsensor_cfg_table.h` tiene la misma forma en 4.19 y 6.6:
  `IMGSENSOR_I2C_DRV_NAME_0..8` (`kd_camera_hw`, `..._bus2`, …) y
  `IMGSENSOR_I2C_OF_DRV_NAME_n` → `mediatek,camera_main|camera_sub|
  camera_main_two|camera_sub_two|camera_main_three|…`.
- Mapa slot→bus en ruby 4.19: MAIN→DEV_0, SUB→DEV_1, MAIN2→**DEV_2**,
  SUB2→DEV_3, MAIN3→DEV_1, SUB3→DEV_5, MAIN4→DEV_6.
  Mapa del A34 6.6: MAIN→DEV_0, SUB→DEV_1, MAIN2→**DEV_1**, SUB2→DEV_3,
  MAIN3→DEV_2. El dtbo de ruby pone cam1 y cam2 en i2c2 (DEV_1), así que el
  mapa del A34 encaja mejor con el DTS de ruby que su propia tabla de 4.19.
  **Sin resolver**: falta el DTS base de ruby (en el lab solo está el dtbo)
  para fijar `IMGSENSOR_I2C_DEV_n` → bus de Linux.
- Para añadir un sensor en 6.6: directorio en `src/common/v1_1/<sensor>_mipi_raw/`
  (sin proyecto) o en `src/isp6s*/camera_project/<proyecto>/`; entrada en
  `imgsensor_sensor_list.c` (`{ID, SENSOR_DRVNAME_x, x_MIPI_RAW_SensorInit}`
  bajo `#if defined(X_MIPI_RAW)`); id y drvname en `inc/kd_imgsensor.h`;
  y el nombre en `CONFIG_CUSTOM_KERNEL_IMGSENSOR` del defconfig (eso genera el
  `-DX_MIPI_RAW`). Opcional: `CONFIG_IMGSENSOR_MAIN/SUB/...` con
  `SPECIFY_IMGSENSOR`.
- El A34 ya define `OV02B10_SENSOR_ID 0x002b` y su drvname, y tiene la entrada
  `#if defined(OV02B10_MIPI_RAW)` en la lista, pero **el directorio del driver
  no existe**: activarlo rompe el enlazado.

## 5. Userspace

No verificable en este workspace. `docs/104-gaps-vivos.md` ya documenta que el
`mtkcam` del vendor de ruby es isp7/isp8 (estilo V4L2, coincide con
`src-isp8`/`src-v4l2`) y por tanto no puede hablar con el driver isp6s de
kernel (ioctl/proc). No hay HAL ni blob de cámara de ruby en el lab
(`device/live/` solo tiene listas de módulos), así que la compatibilidad
HAL↔kernel no se puede demostrar aquí.

## 6. Plan mínimo, en orden

1. Registrar **imx766** (ya está en el A34) y **ov16a1q** (variante sobre Volla)
   para validar la tubería isp6s de punta a punta en cam0/cam1.
2. Portar **ov02b10** (~1,7 k líneas, el más pequeño).
3. Portar **s5khpx** (15–21 k líneas) desde el 5.10 de tanzanite: es el sensor
   principal, pero también el más caro.
4. Decidir Kconfig: `CONFIG_MTK_IMGSENSOR` (isp6s) frente a `ISP6S_MON` (lo que
   usa el A34), y si se conserva el layout `camera_project/k6877v1_64_k419` de
   ruby o se aplana en `common/v1_1`.

## Incógnitas explícitas

- Mapa bus i2c ↔ `IMGSENSOR_I2C_DEV_n` (falta el DTS base de ruby).
- Strap i2c de cam0: la tabla del driver dice `0x20`, el dtbo dice `0x34`
  (el A34 tiene el mismo tipo de desajuste, así que el `reg` del dtbo no es
  autoritativo).
- Compatibilidad del HAL de cámara del vendor con el kernel isp6s.
