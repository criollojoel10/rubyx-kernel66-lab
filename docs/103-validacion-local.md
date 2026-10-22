# 103 — Validación local antes de lanzar CI

Un build de CI tarda **~40 minutos** (Kleaf/Bazel compila el GKI entero y
los device modules). Un port mal hecho se detecta a los 40 minutos, una vez
y otra. Este flujo compila **solo** los drivers portados, en el host, en
minutos.

## Requirements

```sh
pacman -S --needed gcc make bc bison flex python3
```

`clang`/`lld` no hacen falta: el kernel se compila con gcc en local (el
mirror de ArchLinuxARM da 404 para clang 23). `bc` es imprescindible: sin
él falla `include/generated/timeconst.h`.

## El ciclo

```sh
# 1. compilar un target (el fixer resuelve solo los headers que falten)
./scripts/build-target-local.sh drivers/input/touchscreen/focaltech_3680/

# 2. compilar todos los ports y ver el resumen
./scripts/check-ports-local.sh
```

`check-ports-local.sh`:

1. aplica los ports (`port/apply-all.sh`): display, táctil, carga, TEEI 400,
   mediatek_v2 y el fragmento de config;
2. reproduce el **merge real del build**: `merge_config.sh` con
   `mediatek-bazel_defconfig` + `sec_ogki_fragment` + `mt6877_overlay` +
   `mt6877_teegris_5_overlay` + `sign.config`, con
   `KCONFIG_EXT_PREFIX=../kernel/kernel_device_modules-6.6/`;
3. compila driver a driver con `make <ruta>` (que es lo que hace el build).

## El fixer de headers

Los drivers de MTK 6.6 (mediatek_v2, TEEI 400) arrastran headers que el
GKI del A34 no trae. `build-target-local.sh` ante un
`fatal error: <header>: No such file` lo busca en los device modules, en el
árbol público de MTK 6.6 (Volla) y en el propio GKI, y lo copia al GKI
reintentando la compilación:

| Header | Destino en el GKI |
|---|---|
| `uapi/drm/mediatek_drm.h` | `include/uapi/drm/` |
| `linux/soc/mediatek/mtk-cmdq-ext.h` | `include/linux/soc/mediatek/` |
| `linux/mailbox/mtk-cmdq-mailbox-ext.h` | `include/linux/mailbox/` |

Los que el fixer descubre se añaden a `port/mtk-drivers/apply.sh` para que
el CI los copie también (el CI no tiene el fixer).

## Cuando sale limpio

```sh
git add -A && git commit -m "..."     # los ports y los headers
gh workflow run -R criollojoel10/rubyx-kernel66-lab build-ruby-full.yml --ref main
```

Y cuando el build de CI sea verde:

```sh
./scripts/test-ruby-kernel.sh <run-id>    # empaqueta, flashea en B, verifica
```

## Errores típicos que aparecen aquí

| Error | Causa |
|---|---|
| `timeconst.h Error 127` | falta `bc` |
| `uapi/drm/mediatek_drm.h: No such file` | header UAPI de MTK ausente en el GKI |
| `must use 'struct' tag to refer to type 'TEEC_Context'` | el include path de TEEGRIS debe ir **antes** del de teei |
| `undefined! bootprof_log_boot` | `CONFIG_MICROTRUST_TZ_DRIVER_MTK_BOOTPROF=n` (el símbolo está en los device modules, que no se compilan) |
| `illegal rule name: .../../vendor/...` | bazel no admite rutas `../` en las listas de outs de Kleaf |
| `mediatek_drm.h: unknown type name 'uint32_t'` | el header UAPI de MTK no incluye los tipos base; con el PCH de clang falla (gcc local no lo detecta) -> `port/mtk-drivers/apply.sh` le añade `linux/types.h` |
