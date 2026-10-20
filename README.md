# rubyx-kernel66-lab

Laboratorio reproducible del port **Ruby/Rubyx 4.19 → 6.6**. El objetivo de
este repositorio es construir un kernel 6.6 nuevo para el Xiaomi Redmi Note 12
Pro 5G (`ruby`, MT6877V), usando:

- **Samsung Galaxy A34 5G (a34x, MT6877)** como base MTK 6.6 ejecutable;
- **RubyxLabs/kernel_xiaomi_mt6877 4.19** como especificación del hardware;
- **ACK android15-6.6** como núcleo Android común;
- el **kernel 6.6 de ruby ya publicado** como oráculo binario.

## Estado

| Hito | Estado |
|---|---|
| 0. Congelar oráculos | pendiente |
| 1. Compilar A34 6.6.127 sin modificaciones | **en curso** |
| 2. Inventario diferencial Ruby 4.19 vs A34 6.6 | pendiente |

## Hito 1

Referencia exacta:

```
repo     https://github.com/UN1CA/kernel_samsung_a34x
tag      6.6.127_2026-04-06_A346BXXSEEZB6
commit   f1a63bfb4bc3a93aefee99308535c3c1c39b0776
kernel   6.6.127
submódulo kernel-6.6
         UN1CA/kernel_samsung_mediatek_common @ 2415ac269f13919d8c855f495cb141268e8751bb
```

El build es el oficial del árbol: `build_kernel.sh` sincroniza
`common-android15-6.6` con `repo`, descarga Clang `r536225` y ejecuta
Kleaf/Bazel con `mediatek-bazel_defconfig` + overlays de MT6877.

```sh
make fetch       # clona el tag y el submódulo exactos
make build       # ejecuta build_kernel.sh, log en logs/
make collect     # recoge Image, DTB, .config, Module.symvers, .ko, hashes
make verify      # valida versión, formato y coherencia
```

En GitHub Actions: workflow **Build A34 6.6.127 reference**.

## Reglas

1. No se porta todavía código de Ruby.
2. No se modifican drivers para que compile.
3. No se ocultan errores con `|| true` ni equivalentes.
4. Todo checkout queda fijado por commit.
5. `Module.symvers` solo se acepta si lo produce el build real.
6. No se declara reproducible hasta una segunda compilación limpia.

## Estructura

```
manifests/      fuentes y toolchain fijados
scripts/        fetch, build, collect, verify
docs/           procedencia, build y siguiente paso
artifacts/      salidas (ignoradas por git)
sources/        checkouts (ignorados por git)
```
