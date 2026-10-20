# 09 — Fuente de LineageOS 24 usada por la ROM

## Identidad de la ROM

Extraída de `system.img` (`/system/build.prop`) y de
`META-INF/com/android/metadata` del ZIP `rubyx-20261015`:

```
ro.system.build.fingerprint = Redmi/lineage_rubyx/rubyx:17/CP2A.260605.016/eng.aeron:userdebug/release-keys
ro.system.build.id          = CP2A.260605.016
ro.system.build.date        = Wed Oct 14 18:53:58 UTC 2026
ro.build.version.release    = 17
ro.build.version.sdk        = 37
ro.build.version.security_patch = 2026-10-01
ro.build.user               = aeron
ro.build.host               = lab
ro.lineage.device           = rubyx
```

La release se describe como **LineageOS 24.0 basada en Android 17 QPR0**
(beta). El `vendor.img` confirma:

```
ro.vendor.build.id          = CP2A.260605.016
ro.vendor.build.version.release = 17
ro.vendor.build.version.sdk = 37
ro.vendor.build.date        = Tue Oct 13 14:29:01 UTC 2026
```

## Qué es público

| Repo | Rama | Commit | Estado |
|---|---|---|---|
| `LineageOS/android` | `lineage-24.0` | — | público |
| `RubyxLabs/device_xiaomi_rubyx` | `lineage-24.0` | `2361c67d0844` | público |
| `RubyxLabs/vendor_xiaomi_rubyx` | `lineage-24.0` | `1d9766def986` | público |
| `RubyxLabs/hardware_mediatek` | `lineage-24` | `5fa9973471e3` | público |
| `LineageOS/android_hardware_mediatek` | `lineage-24.0` | `74e1500193df` | público |

El device tree 24.0 incluye face unlock, Dolby, cámara y overlays; el vendor
24.0 incluye los blobs de `proprietary/`, `product/` y `system_ext/`.

## Qué NO es público

| Repo | Rama que necesita el build | Estado |
|---|---|---|
| `kernel/xiaomi/mt6877` | 6.6 (`ruby_defconfig`) | **privado / no publicado** |
| `hardware/xiaomi` | 24.0 | solo hay `lineage-23.0` público (`01486f4a`) |
| `vendor/mediatek/ims` | 24.0 | solo hay `lineage-23.0`/`lineage-23.2` público (`d753733f`) |
| `vendor/xiaomi/miuicamera-rubyx` | 24.0 | solo `lineage-23.0`/`23.1` público |

`BoardConfig.mk` del device 24.0 lo confirma:

```make
TARGET_KERNEL_SOURCE := kernel/xiaomi/mt6877
TARGET_KERNEL_CONFIG := ruby_defconfig
TARGET_KERNEL_CLANG_VERSION := r563880c
```

El repo público `RubyxLabs/kernel_xiaomi_mt6877` solo tiene ramas 4.19
(`lineage-23.0/23.1/23.2`); su último commit es de 2025-12-13. El árbol 6.6
que usa la ROM no está publicado.

## Conclusión

**La base LineageOS 24 y casi todo el device tree son públicos. El build
completo no lo es:** faltan el kernel 6.6 y las ramas 24 de
`hardware/xiaomi` y `vendor/mediatek/ims`.

No es que “LineageOS 24 sea privado”; es que el maintainer
(`Aeron-Aeron`, `aeronrules2@gmail.com`, Telegram `aeronruless`) mantiene
privadas esas tres piezas. Sin ellas se puede auditar el device tree, el
vendor y los blobs, pero no reconstruir la ROM completa.

## Local manifest mínimo (solo partes públicas)

`repo init -u https://github.com/LineageOS/android -b lineage-24.0 --git-lfs`

```xml
<manifest>
  <project name="RubyxLabs/device_xiaomi_rubyx"
           path="device/xiaomi/rubyx" remote="github" revision="lineage-24.0" />
  <project name="RubyxLabs/vendor_xiaomi_rubyx"
           path="vendor/xiaomi/rubyx" remote="github" revision="lineage-24.0" />
  <project name="LineageOS/android_hardware_mediatek"
           path="hardware/mediatek" remote="github" revision="lineage-24.0" />
  <!-- Faltan, y sin ellas no hay build completo:
       hardware/xiaomi            (24.0)
       vendor/mediatek/ims        (24.0)
       kernel/xiaomi/mt6877       (6.6)
  -->
</manifest>
```

Build, cuando existan las piezas privadas:

```sh
source build/envsetup.sh
lunch lineage_rubyx-userdebug
make bacon
```

## Caché de la ROM

`Aeron-Aeron/ROMBuilder-CI` (plantilla genérica, no el manifest de ruby) usa
`ccache` con `ccache -M 100G` para las builds de ROM. Eso no aplica al kernel
Kleaf, que no soporta ccache; para el kernel seguimos con Bazel.
