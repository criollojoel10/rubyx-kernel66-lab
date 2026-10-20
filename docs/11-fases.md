# 11 — Plan por fases del port

## Estado

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Build de referencia A34 6.6.127 | ✅ PASS |
| 1 | Inventario de `compatible` ruby vs A34 | ✅ hecho |
| 2 | Alias + auditoría de headers/API de los drivers | ✅ hecho |
| 3 | Configuración mínima ruby 6.6 | ▶ siguiente |
| 4 | Device Tree mínimo | ✅ scaffold compilado |
| 5 | Compilar y arrancar a consola | ▶ arquitectura decidida |
| 6 | Almacenamiento, init de Android, ADB | pendiente |
| 7 | Pantalla, touch, carga, audio, cámara | pendiente |
| 8 | Droidspaces con PID/IPC/SYSVIPC built-in | pendiente |

## Fase 2 — Resultado

De los 171 `compatible` solo-ruby:

```
33  reserved-memory   (DTS, no código)
34  driver-in-a34     (ya existe)
11  alias-a34         (misma cosa con mt6359p o guion)
 5  fallback-a34      (compatible genérico)
63  port-driver       (candidato a portar)
10  fallback-ruby     (genérico en 4.19)
15  dts-only          (sin driver identificado)
```

### Alias, no port

`alias-a34` cubre el PMIC de arranque:

```
mt6359-accdet, mt6359-auxadc, mt6359-efuse, mt6359-lbat_service,
mt6359-rtc, mt6359_gauge
smi_common, smi_larb, snd_audio_dsp, snd_scp_ultra, usb_boost
```

El A34 ya tiene esos drivers como `mt6359p-*` o con guion. Se resuelven con
alias de `compatible` o ajustando el DTS, sin portar código.

### Auditoría de headers

Sobre los 63 `port-driver`, comparando sus `#include` contra los headers del
A34:

| Resultado | Drivers |
|---|---:|
| Sin includes faltantes | 7 |
| Con algún include faltante | 56 |
| Directorio del driver ausente en A34 | 37 |

Drivers sin includes faltantes (candidatos fáciles):

```
mediatek,idle-state        drivers/cpuidle/cpuidle-mediatek.c
mediatek,mt6768-auxadc     drivers/iio/adc/mt6577_auxadc.c
mediatek,mt67xx-rng        drivers/char/hw_random/mt67xx-rng.c
xiaomi,simtray-status      drivers/misc/simtray.c
goodix,9916r-spi           drivers/input/touchscreen/goodix_9916r/goodix_brl_spi.c
xiaomi-touch               drivers/input/touchscreen/xiaomi/xiaomi_touch.c
```

Headers ausentes más frecuentes:

| Header | Drivers |
|---|---:|
| `linux/hwid.h` | 21 |
| `mt-plat/v1/charger_class.h` | 10 |
| `drm/drmP.h` | 9 |
| `mt-plat/aee.h` | 5 |
| `mt-plat/v1/charger_type.h` | 5 |
| `apusys_power.h` | 4 |
| `mt-plat/mtk_thermal_monitor.h` | 4 |
| `mach/mtk_thermal.h` | 4 |

Lectura:

- `linux/hwid.h`, `mt-plat/*`, `apusys_power.h` son headers downstream de MTK.
  El A34 tiene equivalentes con otro nombre o hay que adaptar el driver.
- `drm/drmP.h` fue eliminado en kernels modernos. Los 3 paneles y parte de
  display necesitan port real a DRM 6.6, no solo copiar el `.c`.
- `mt-plat/v1/charger_class.h` afecta a los 20 drivers de carga; el A34 usa
  `power_supply` moderno y su propio `charger_class`. Es el grupo más costoso.

### Conclusión de fase 2

- El arranque inicial **no requiere** portar los 63: PMIC, UART, I2C, SMI y
  storage están cubiertos por drivers del A34 o alias.
- El trabajo real de código se concentra en carga (20), cámara/vídeo (14),
  display (10), touch/fingerprint (5), audio/háptica (2) y APU (4).
- Los paneles y charger son los bloques con más riesgo de API.

## Fase 3 — Configuración mínima

Objetivo: `ruby_earlycon_defconfig` compilable, con:

- base `mediatek-bazel_defconfig` + `mt6877_overlay.config`;
- drivers MTK mínimos para consola, PMIC, storage, watchdog e IOMMU;
- `PID_NS`, `IPC_NS`, `SYSVIPC`, `POSIX_MQUEUE` built-in desde el inicio;
- sin drivers Xiaomi específicos todavía.

Criterios:

```
CONFIG_ARCH_MEDIATEK=y
CONFIG_MTK_PLATFORM="mt6877"
CONFIG_SERIAL_8250_MT6577=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_SYSVIPC=y
```

## Fase 4 — Device Tree mínimo

Nodos: CPU, GIC, timer, PSCI, UART, pinctrl, clocks, PMIC (alias
`mt6359p-*`), storage, watchdog e `reserved-memory` indispensable.

Criterio: `dtc` sin errores, `fdtget` lee modelo/compatible, sin phandles
rotos.

## Fase 5 — Primer arranque

Evidencia mínima:

```
Booting Linux on physical CPU
Linux version 6.6.127
Machine model: Xiaomi ruby
GIC initialized
clocksource initialized
Freeing unused kernel memory
```

## Fase 6 — Android

UFS/eMMC, dm-verity, F2FS/ext4, ramdisk, init, SELinux, ADB.

## Fase 7 — Periféricos

Pantalla/touch, carga/batería, USB, audio, conectividad, cámara,
fingerprint, háptica, sensores.

## Fase 8 — Droidspaces

PID/IPC/SYSVIPC ya built-in; validar `unshare -p/-i`, cgroups, overlayfs,
veth/bridge y arranque de un init como PID 1.
