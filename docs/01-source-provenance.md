# 01 — Procedencia de fuentes

Todo queda fijado por commit en `manifests/a34-6.6.127.lock.json`.

| Elemento | Valor |
|---|---|
| Repositorio | `https://github.com/UN1CA/kernel_samsung_a34x` |
| Tag | `6.6.127_2026-04-06_A346BXXSEEZB6` |
| Commit | `f1a63bfb4bc3a93aefee99308535c3c1c39b0776` |
| Kernel | 6.6.127 |
| OSRC | `A346BXXSEEZB6` |
| Submódulo | `kernel-6.6` |
| URL submódulo | `https://github.com/UN1CA/kernel_samsung_mediatek_common` |
| Commit submódulo | `2415ac269f13919d8c855f495cb141268e8751bb` |
| Toolchain | Clang `r536225` |
| Manifest AOSP | `common-android15-6.6` |

## Verificación

```sh
git -C sources/a34x rev-parse HEAD
git -C sources/a34x/kernel-6.6 rev-parse HEAD
sed -n '1,4p' sources/a34x/kernel-6.6/Makefile
```

Debe imprimir `6.6.127` en `SUBLEVEL`.

## Nota sobre `.gitmodules`

El `.gitmodules` del tag declara:

```
branch = 558e607c8e4c579a6b3d2d5f4c3ea0a39a526937
```

Ese campo no es una rama, es un SHA que **no** coincide con el commit real del
submódulo (`2415ac...`). El checkout válido es el gitlink del superproyecto, no
ese campo. El script de fetch verifica el SHA real y falla si no coincide.
