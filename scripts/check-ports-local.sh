#!/usr/bin/env bash
# Validacion LOCAL de los ports de ruby: compila los drivers contra el GKI
# de MTK 6.6 sin necesidad del CI (40 min por build).
#
# Usa el .config real del build (artifacts/.../device-modules.config), le
# fusiona los fragments de ruby y compila uno a uno los drivers que
# portamos. Asi se detectan los errores de API 4.19->6.6 en segundos.
#
# Uso: scripts/check-ports-local.sh [objetivo...]
#        (sin argumentos: todos)
set -uo pipefail
cd "$(dirname "$0")/.."

GKI="sources/a34x/kernel-6.6"
DM="sources/a34x/kernel/kernel_device_modules-6.6"
REF="artifacts/a34-6.6.127/device-modules.config"

[ -d "$GKI" ] || { echo "falta $GKI; ejecuta make fetch" >&2; exit 1; }
[ -f "$REF" ] || { echo "falta $REF (config de referencia)" >&2; exit 1; }

# objetivos: nombre:ruta-a-compilar
OBJETIVOS=(
  "panel:drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.o"
  "touch:drivers/input/touchscreen/focaltech_3680/"
  "mp2762:drivers/power/supply/mps/"
  "bq25980:drivers/power/supply/ti/"
  "sc8551:drivers/power/supply/southchip/"
  "max77932:drivers/power/supply/maxim/"
  "xmusb350:drivers/power/supply/xiaomi/"
  "teei:drivers/tee/teei/400/"
  "mediatek_v2:drivers/gpu/drm/mediatek/mediatek_v2/"
)

if [ "$#" -gt 0 ]; then
  FILTRO="$*"
else
  FILTRO=""
fi

echo "== 1. aplicando los ports al arbol"
./port/apply-all.sh sources/a34x >/dev/null || { echo "apply-all fallo" >&2; exit 1; }

echo "== 2. preparando el .config (merge real del build)"
cd "$GKI"
export KCONFIG_EXT_PREFIX=../kernel/kernel_device_modules-6.6/
cp "$OLDPWD/$REF" .config
./scripts/kconfig/merge_config.sh -m .config \
  ../kernel/kernel_device_modules-6.6/arch/arm64/configs/mediatek-bazel_defconfig \
  ../kernel/kernel_device_modules-6.6/kernel/configs/sec_ogki_fragment.config \
  ../kernel/kernel_device_modules-6.6/kernel/configs/mt6877_overlay.config \
  ../kernel/kernel_device_modules-6.6/kernel/configs/mt6877_teegris_5_overlay.config \
  ../kernel/kernel_device_modules-6.6/kernel/configs/sign.config >/dev/null 2>&1
# sin clang/lto en local: se compila con gcc
sed -i -e 's/^CONFIG_CC_IS_CLANG=y/# CONFIG_CC_IS_CLANG is not set/' \
       -e 's/^CONFIG_LTO_CLANG=y/# CONFIG_LTO_CLANG is not set/' \
       -e 's/^CONFIG_CFI_CLANG=y/# CONFIG_CFI_CLANG is not set/' .config
make -s olddefconfig CC=gcc HOSTCC=gcc >/dev/null 2>&1
echo "   .config listo ($(wc -l < .config) lineas)"

echo "== 3. compilando los ports"
fallos=0
for o in "${OBJETIVOS[@]}"; do
  nombre="${o%%:*}"; ruta="${o#*:}"
  case " $FILTRO " in *" $nombre "*) ;; *) continue ;; esac

  # solo los targets que el config habilita
  case "$nombre" in
    panel) sym=CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO ;;
    touch) sym=CONFIG_TOUCHSCREEN_FOCALTECH_3680 ;;
    mp2762) sym=CONFIG_RUBY_MP2762 ;;
    bq25980) sym=CONFIG_RUBY_BQ25980 ;;
    sc8551) sym=CONFIG_RUBY_SC8551 ;;
    max77932) sym=CONFIG_RUBY_MAX77932 ;;
    xmusb350) sym=CONFIG_RUBY_XMUSB350 ;;
    teei) sym=CONFIG_MICROTRUST_TEE_SUPPORT ;;
    mediatek_v2) sym=CONFIG_DRM_MEDIATEK_V2 ;;
  esac
  if ! grep -qE "^${sym}=(m|y)" .config; then
    echo "   --  $nombre: deshabilitado en el config ($sym)"
    continue
  fi

  printf "   %-12s " "$nombre"
  out=$(timeout 1800 make -j"$(nproc)" CC=gcc HOSTCC=gcc "$ruta" 2>&1)
  if [ $? -eq 0 ] && ! echo "$out" | grep -qE '(^|:) error:'; then
    echo "OK"
  else
    echo "FALLO"
    fallos=$((fallos + 1))
    echo "$out" | grep -E '(^|:) error:|Error [0-9]|undefined reference|No rule to make' \
      | head -12 | sed 's/^/        /'
  fi
done

echo
if [ "$fallos" -eq 0 ]; then
  echo "== todos los ports compilan"
else
  echo "== $fallos target(s) con errores"
fi
exit "$fallos"
