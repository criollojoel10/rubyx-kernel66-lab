# 104 — Gaps reales: inventario en vivo + informes de investigación

Todo lo de aquí está verificado contra el **dispositivo** (root APatch,
kernel 6.6 stock) o contra los árboles de código, no contra suposiciones.

## 1. Lo que YA funciona en el kernel stock de ruby

| Subsistema | Evidencia en vivo |
|---|---|
| TEE / FBE | `/dev/isee_tee0`, `/dev/teei_client`, `/dev/teei_config`, `/dev/teei_fp`, `/dev/tz_vfs`, `/dev/ut_keymaster`; servicios `keymaster_attestation-1-1`, `soter-1-0`, `teei_daemon`, `vendor.keymaster-4-1-beanpod`; dmesg `[tz_driver] TEEI UT IRQ367 HANDLED CPU0` |
| Huella | `/dev/goodix_fp`; `dumpsys fingerprint` con prints, `HAL deaths 0`; input `uinput-goodix` |
| Display | `card0-DSI-1 connected 1080x2400`; dmesg con `drm_invoke_fps_chg_callbacks` |
| Táctil | input `fts_ts` (event3) = Focaltech **FT3680** por SPI3 |
| Audio | ALSA `card0` (mt6877-mt6359) + **aw882xx** (Awinic 7-0034/7-0035) |
| Cámara | 5 cámaras (`Number of camera devices: 5`), nodos `/dev/camera-{dip,dpe,fdvt,isp,mfb,rsc,wpe}` |
| Sensores | 33 h/w activos (HAL Elliptic Labs) |
| GPS | `/dev/gps_emi`, `/dev/gpsdl0`, `/dev/gpsdl1`, `/dev/socket/mnld`; `agpsd` y `vendor.gnss-default` corriendo |
| Carga | `power_supply`: ac, battery, bbc, bms, charger, cp_master, cp_slave, primary_chg, usb; dmesg `mt6360_pmu_chg mt6360-chg.2.auto` |
| Droidspaces (stock) | faltan 2 requisitos: **PID_NS** e **IPC_NS**; opcionales: MACVLAN, IPv6 NAT, CFS_BANDWIDTH, CGROUP_PIDS, USER_NS |

Dos conclusiones que cambiaron el plan:

- **La carga de ruby la hace el cargador del PMIC mt6360**, no el mp2762/
  ln8000/xmusb350 → **los ports de carga sobran** (el A34 ya trae
  `CONFIG_DEVICE_MODULES_CHARGER_MT6360`).
- **El panel real es `m16 42-0d-0a`** (lo dice el cmdline del stock:
  `panel-m16-42-0d-0a-dsc-vdo.oled_wp=...`), no el 36-02-0b → el port se
  rehízo sobre el 42-0d-0a (`scripts/port-m16-panel.py`).

## 2. Gaps confirmados y su veredicto

| Gap | Veredicto |
|---|---|
| **Display** | Port del `m16 42-0d-0a` a la API `mediatek_v2` (DCS y timings sacados del 4.19 de ruby). El DTB de ruby ya usa los compatibles de la v2 (`mediatek,mt6877-disp-ovl`) → **el DTB no se toca** |
| **Táctil** | FT3680 por SPI3 portado (chip id `0x3680008A`). Compila en local |
| **TEE** | Microtrust TEEI 400 built-in (el stock lo tiene built-in también). Solo faltaba el include path de TEEGRIS y `MICROTRUST_TZ_DRIVER_MTK_BOOTPROF=n` |
| **Carga** | **Nada que portar**: mt6360 ya está en el A34 |
| **Firmware** | El GKI 6.6 no busca en `/vendor/firmware` (el 4.19 de ruby sí) → parche `port/kernel-patches/firmware-path.sh` |
| **Huella** | El driver Goodix 6.6 del árbol público (Volla, `goodix-gw9518`) usa la TA de Beanpod (UUID `0x7778c03f`); ruby usa la TA Goodix (`0x8888c03f`) y otro chip → hay que portar el `goodix_cap` del 4.19 de ruby (que ya usa el SPI genérico y el UUID correcto) |
| **Audio** | `aw882xx` (28 k líneas) y `aw8697` (460 KB) no existen en 6.6 → portar del 4.19. Riesgos: `linux/hwid.h` no existe, `class_create()` sin `THIS_MODULE`, API de DAPM, y que la sound card de MTK 6.6 soporte `mediatek,speaker-codec` (`sound-dai`). Hace falta el firmware `.bin` de Awinic |
| **Cámara** | Faltan 4 de los 10 sensores (`s5khpx` x2, `ov02b10` x2). `imx766` y `ov16a1q` existen; `s5k4h7` solo para otra ISP. El módulo vendor `mtkcam` **no** sirve (MT6877 es ISP6s, mtkcam trae isp7/isp8) → portar los sensores al `imgsensor` de kernel 6.6 (`isp6s_mon`); la API es casi idéntica al 4.19 (0-4 líneas de diferencia en los headers) |
| **GPS** | El stack de ruby es DLink v030: `gps_drv_dl_v030.ko` + `conninfra` + `common` de los módulos vendor de MTK 6.6. El vendor de ruby **no** trae `ro.vendor.gps.chrdev` → hay que escribir un `.rc` propio en el ramdisk |
| **NFC / Type-C / LEDs** | `mediatek,nfc` (i2c3@0x08), `mediatek,usb_type_c` (i2c5@0x4e), `mediatek,red/green/blue`, `mediatek,lcd-backlight`, `mediatek,vibrator`, `xiaomi,simtray-status`, `onsemi,fan53870` (i2c0@0x35, 7 rails) → pendientes de auditar contra el árbol 6.6 |
| **WiFi / BT** | El stock los tiene **built-in** (`CONFIG_WLAN_DRV_BUILD_IN=y`) y el vendor es `gen4m`/`wmt_chrdev_wifi` → hay que compilar el stack conninfra/wlan/bt de MTK 6.6 y que encuentre el firmware en `/vendor/firmware` |

## 3. Orden de trabajo

1. **Display + táctil + TEE** (ya portados y compilando) → primer flash de
   prueba: ¿imagen, táctil y FBE? → `scripts/test-ruby-kernel.sh`.
2. **Firmware path** (ya parcheado) → base para WiFi/BT/GPS/audio.
3. **GPS** (módulos vendor + `.rc` propio).
4. **Huella** (port del `goodix_cap` del 4.19 con el UUID Goodix).
5. **Cámara** (4 sensores al `imgsensor` 6.6).
6. **Audio** (aw882xx + aw8697) → el altavoz es lo más visible.
7. **NFC / LEDs / Type-C** (cola larga).

## 4. Verificación

```sh
./scripts/inventario-vivo.sh          # vuelca el estado real del telefono
./scripts/verify-ruby.sh              # contrato kernel <-> user space
./scripts/check-ports-local.sh        # compila los ports en local (minutos)
```

## Carga: verificado en vivo que no hace falta portar nada

El dtsbo de ruby declara cargadores que el kernel stock **no usa** para
cargar. En el dispositivo (kernel 6.6 stock, root) la carga la hace el
cargador del PMIC mt6360:

```
mt6360_pmu_chg mt6360-chg.2.auto: mt6360_dump_registers:
    ICHG = 1500mA, AICR = 1500mA, MIVR = 4200mV, IEOC = 200mA
    VBUS = 4700mV, IBUS = 1347mA, VSYS = 3976mV, VBAT = 3946mV
    CHG_EN = 1, CHG_STATUS = progress
```

`/sys/class/power_supply`: ac, battery, bbc, bms, charger, cp_master,
cp_slave, primary_chg, usb.

Cruce de compatibles (DTB de ruby -> driver en el GKI 6.6 del A34):

| DTB de ruby | Driver en el GKI | Nota |
|---|---|---|
| `mp2762` | `mp2762` (mps) | existe |
| `xmusb350` | `xmusb350` (xiaomi) | existe |
| `max77932` | `max77932` (maxim) | existe |
| `sc8561_master/slave` | `sc8561` | existe |
| `ti,bq28z610` | `bq28z610` | el driver declara "bq28z610", no "ti,bq28z610" |
| `bq25980_standalone1/2/3` | `ti,bq25980` | no coincide el compatible |
| `sc8551_i2c7/11` | - | no esta en el GKI |
| `lionsemi,ln8000` | - | no esta en el GKI |

**Conclusion**: la carga de ruby va por el mt6360 (que el A34 ya trae como
`CONFIG_DEVICE_MODULES_CHARGER_MT6360`), asi que los ports de carga no son
necesarios para que el telefono cargue. `port/charger/` queda como
referencia por si se quiere el soporte completo de USB-PD.
