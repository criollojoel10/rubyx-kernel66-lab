# 102 — Estado del kernel 6.6 de ruby (2026-10-22)

## Resumen

| Subsistema | Estado | Detalle |
|---|---|---|
| Base del kernel | **OK** | GKI de MTK 6.6.127 (A34 = Exynos 1380 = **MT6877**, el SoC de ruby) + device modules de MTK para MT6877 |
| Device Tree | **OK** | El DTB 6.6 de ruby ya esta extraido y se usa tal cual; el `dtbo` de ruby se queda en su particion |
| Display | **portado** | Panel real de ruby = **m16 42-0d-0a** (lo dice el cmdline del stock: `panel-m16-42-0d-0a-dsc-vdo.oled_wp=...`), portado a la API `mediatek_v2` en `port/display/` |
| Tactil | **portado** | Focaltech **FT3680** por SPI3 (`focaltech,3680-spi`), en `port/touch/` |
| TEE (keymaster/FBE) | **portado** | Microtrust **TEEI 400** copiado de los device modules al GKI y compilado built-in, como en el stock |
| Huella | **portado** | `goodix_cap` (TA Goodix `0x8888c03f`) del 4.19 de ruby, en `port/fingerprint/` |
| Carga | **sin ports** | ruby carga con el **PMIC mt6360** (`mt6360-chg.2.auto`), que el A34 ya trae |
| Audio | **portado, sin compilar** | Altavoz **aw882xx** (28 k lineas) y vibrador **aw8697** en `port/audio/` |
| GPS | **pendiente** | Stack **DLink v030** (`gps_drv_dl_v030.ko` + conninfra + common) de los modulos vendor MTK 6.6; falta el `.rc` (el vendor de ruby no trae `ro.vendor.gps.chrdev`) |
| Camara | **pendiente** | Faltan los sensores `s5khpx` x2 y `ov02b10` x2 en el `imgsensor` de 6.6; el modulo vendor `mtkcam` no sirve (MT6877 es ISP6s) |
| Sensores / NFC / LED / Type-C | **pendiente** | 38 nodos del dtbo sin driver (ver `docs/104-gaps-vivos.md`) |
| Droidspaces | **en build** | Parche kABI oficial + config GKI + fragment `release.fragment` |
| Flash de prueba | **OK** | `scripts/test-ruby-kernel.sh <run>`: artefacto -> boot.img -> slot B (tries=1) -> verificacion |

## Lo que se aprendio leyendo el telefono (no el codigo)

Inventario en vivo (`scripts/inventario-vivo.sh`, salida en
`docs/evidence/inventario-vivo-2026-10-22.txt`):

- El **TEE** de ruby es Microtrust TEEI 400: `/dev/isee_tee0`, `/dev/teei_client`,
  `/dev/ut_keymaster`, con `teei_daemon` y `keymaster` beanpod corriendo.
- La **huella** es Goodix por SPI (`/dev/goodix_fp`, input `uinput-goodix`).
- El **altavoz** es `aw882xx` (Awinic 7-0034/7-0035) y el **vibrador** `awinic_haptic`.
- La **carga** va por el PMIC mt6360 (`mt6360-chg.2.auto`), no por los cargadores
  del dtbo.
- El **display** es `card0-DSI-1 connected 1080x2400` y el **tactil** `fts_ts`
  (Focaltech).
- El **GNSS** de ruby es DLink v030 (`gps_drv_dl_v030.ko` + conninfra + common).
- El `fw_path[]` del GKI 6.6 **no incluye `/vendor/firmware`** (el 4.19 de ruby
  si) -> parcheado en `port/kernel-patches/firmware-path.sh`.

## Como se compila cada cosa (resumen)

- El GKI se compila con el `.config` de los device modules.
- Los device modules **no se compilan** con `CONFIG_DEVICE_MODULES_ALLOW_BUILTIN=n`:
  lo que ruby necesita (TEEI 400, mediatek_v2) se **copia al GKI**.
- Los drivers de display, tactil, huella y audio tambien van al GKI (en los
  device modules no hay `drivers/input/Makefile` ni `drivers/gpu/drm/Makefile`,
  asi que el kbuild no desciende).
- Todos los drivers de ruby van **built-in (=y)**, como en el stock: no hay
  `.ko` que declarar en las listas de Kleaf.
- La API de display es la **v2** (`mediatek_v2`): el DTB de ruby usa
  `"mediatek,mt6877-disp-ovl"`, que solo matchea la v2.

Detalle completo en `docs/101-arquitectura-build-mtk.md`.

## Ciclo de trabajo

```sh
# 1. validar en local (minutos, no 40 de CI)
./scripts/check-ports-local.sh

# 2. build en CI
gh workflow run -R criollojoel10/rubyx-kernel66-lab build-ruby-full.yml --ref main

# 3. empaquetar, flashear en B (auto-retorno) y verificar
./scripts/test-ruby-kernel.sh <run-id>
```
