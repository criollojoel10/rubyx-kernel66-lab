# 90 — Cierre del kernel 6.6 de ruby: qué falta y cómo queda listo

Definición de "listo": un solo comando produce el kernel, se flashea con
autorreparación y un script verifica todo. Nada de pasos manuales.

## 1. Cadena ya cerrada

```
kernel 6.6.127 (ACK, A34 como base)   OK
UFS 256 GB / 77 particiones           OK
super, userdata, metadata, misc       OK
Android B arranca hasta vold/keystore  OK
TEE Microtrust (isee.ko)               en CI
Droidspaces: PID/IPC ns + kABI patch  en CI
APatch + selfheal slot B->A           OK
```

## 2. Subsistemas que faltan, con su dueño y su criterio

| Subsistema | Qué hay que traer | Criterio de aceptación |
|---|---|---|
| Display | panel m16 reescrito sobre `mediatek_v2` (nueva API `mtk_panel_ctx`), nodo `dsi0` en el DTS, panel1/2/3 | `/sys/class/drm` con connector DSI y framebuffer activo |
| Touch | `xiaomi_touch` + reutilizar `focaltech_touch`/`GT9895` del A34 | `getevent` con toques y multitáctil |
| Carga | `mtk_charger` + `ln8000` (+`bq25980`, `sc8551/8561`), `hwid.c` | `/sys/class/power_supply` con battery, mtk_charger y charger USB; carga real |
| USB/ADB | `mtu3`/`xhci` y gadget USB del A34 | `adb devices` con el teléfono en B |
| GPS | el driver `gnss` ya está en el A34 (`gnss: GNSS driver registered`); falta validar con el firmware de vendor | fix GPS con HAL de ruby, sin crash en `gnss` |
| Audio | `aw882xx` (speaker), `mt6359-accdet` (jack) | `dumpsys media.audio_flinger` con salida |
| Cámara/ISP | sensores Xiaomi + `mtk_vcam` | preview en AOSP Camera |
| Fingerprint | `goodix`/`fpc` TEE | desbloqueo con huella |
| SELinux/AVB | política: empezar permisivo en test; AVB: `vbmeta` stock + boot sin firmar (unlocked) | arranque limpio sin `avc: denied` bloqueantes |
| Droidspaces | kABI patch + `IPC_NS`/`PID_NS`/`SYSVIPC` | `droidspaces check` con 0 must-have fallidos |

## 3. Orden de trabajo y paralelismo

1. **Display** (camino largo, bloquea la UI) — reescritura del panel.
2. **Touch** y **carga** en paralelo (mismo panel ya funcionando).
3. **USB/ADB** y **audio** (rápidos, reutilizan A34).
4. **GPS** (validación, no código) y luego **cámara/fingerprint**.
5. **Droidspaces** al final, con el kernel que ya arranca Android.

## 4. Estructura final del repo

```
port/display/     panel m16 + apply.sh + notas
port/touch/       xiaomi_touch + apply.sh
port/charger/     ln8000 + hwid + apply.sh
port/device/      selfheal (bctool, 99-ruby-selfheal.sh, first-stage-init.sh)
configs/ruby-6.6/  microtrust.fragment, droidspaces-gki.fragment, storage.fragment
scripts/          build, flash, verify, check-kabi
.github/workflows/ builds en CI (core, microtrust, droidspaces+kABI, panel)
docs/             37 UFS, 42 selfheal, 43/44 TEE, 46 Droidspaces, 90 este
```

Cada `port/<subsistema>/apply.sh` es idempotente y se aplica sobre
`sources/a34x/kernel/kernel_device_modules-6.6` antes de compilar.

## 5. Pipeline final

```sh
# 1.构建 (CI o local)
RUBY_OVERLAY=configs/ruby-6.6/microtrust.fragment make build-fast
# 2. empaquetado
scripts/build-ruby-boot.sh    # Image.gz + DTB parcheado + ramdisk con módulos
# 3. flash seguro (slot B, tries=1, APatch, selfheal)
scripts/flash-ruby-slot-b.sh  # backup de boot_b/misc, marca B, reboot
# 4. verificación
scripts/verify-ruby.sh        # UFS, dmesg, DRM, input, power_supply, adb,
                              # droidspaces check, GNSS, pstore
```

## 6. Lo que NO se puede prometer

- **SELinux**: la política de vendor de ruby espera el kernel stock; con el
  nuestro habrá `avc: denied` no bloqueantes. Se empieza permisivo y se
  estrecha por fases.
- **AVB/OTA**: nuestro `boot.img` no está firmado por el release; la
  actualización OTA no podrá validar la partición boot hasta rehacer la
  firma o usar `vbmeta` de pruebas.
- **Cámara**: los sensores Xiaomi con ISP propio son el bloque más caro
  después de display; se puede dejar fuera de la primera versión.
- **`--cpus` y `--pids-limit`** de Droidspaces: desactivados a propósito
  (rompen el kABI), según la doc oficial.

## 7. Definición de "todo listo"

- `droidspaces check`: 0 must-have fallidos.
- Pantalla con imagen estable y touch funcionando.
- Carga USB real con batería en `/sys/class/power_supply`.
- `adb devices` responde desde el slot B.
- GPS con fix.
- Un solo comando de build y otro de verificación, ambos en CI.
