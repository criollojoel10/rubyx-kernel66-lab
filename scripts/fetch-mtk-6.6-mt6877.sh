#!/usr/bin/env bash
# Trae el arbol MTK 6.6 para MT6877 (GKI + device modules) que sirve de base
# al kernel de ruby. Fuentes publicas (ver docs/91-base-mtk-6.6-mt6877.md).
#
# Uso: scripts/fetch-mtk-6.6-mt6877.sh [destino]
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-sources/mtk-6.6-mt6877}"
REF="volla-16.0"

KERNEL_REPO="https://github.com/HelloVolla/android_kernel_volla_mt6877.git"
MODULES_REPO="https://github.com/HelloVolla/android_kernel_device_modules_volla_mt6877.git"

mkdir -p "$DEST"

clone() {
  local url="$1" dir="$2"
  if [ -d "$dir/.git" ]; then
    echo "[mtk] $dir ya esta; actualizando"
    git -C "$dir" fetch --depth 1 origin "$REF"
    git -C "$dir" checkout -q FETCH_HEAD
  else
    echo "[mtk] clonando $url @ $REF"
    git clone --depth 1 --branch "$REF" "$url" "$dir"
  fi
}

clone "$KERNEL_REPO"  "$DEST/kernel"
clone "$MODULES_REPO" "$DEST/kernel_device_modules"

echo
echo "[mtk] contenido clave verificado:"
check() {
  if [ -e "$2" ]; then
    echo "  OK   $1"
  else
    echo "  FALTA $1  ($2)"
  fi
}

check "GKI 6.6 (Makefile)"            "$DEST/kernel/Makefile"
check "gki_defconfig"                 "$DEST/kernel/arch/arm64/configs/gki_defconfig"
check "build.config.gki.aarch64"      "$DEST/kernel/build.config.gki.aarch64"
check "abi (abi.bzl)"                 "$DEST/kernel/abi.bzl"
check "TEEI 400 (Microtrust)"         "$DEST/kernel_device_modules/drivers/tee/teei/400"
check "TEEI 510"                     "$DEST/kernel_device_modules/drivers/tee/teei/510"
check "mediatek_v2 (display)"        "$DEST/kernel_device_modules/drivers/gpu/drm/mediatek/mediatek_v2"
check "panel n11a DSC VDO (ref)"     "$DEST/kernel_device_modules/drivers/gpu/drm/panel/panel-n11a-42-02-0a-dsc-vdo.c"
check "cust_panel (LCM HAL)"          "$DEST/kernel_device_modules/drivers/gpu/drm/panel/cust_panel"
check "focaltech SPI (FT3519)"       "$DEST/kernel_device_modules/drivers/input/touchscreen/focal_FT3519/focaltech_spi_v2.c"
check "carga MTK (mtk_charger)"       "$DEST/kernel_device_modules/drivers/power/supply/mtk_charger.c"
check "DTS mt6877"                   "$DEST/kernel_device_modules/arch/arm64/boot/dts/mediatek/mt6877.dts"
check "DTS referencia k6877v1_64"     "$DEST/kernel_device_modules/arch/arm64/boot/dts/mediatek/k6877v1_64.dts"

grep -m1 '^VERSION\|^PATCHLEVEL\|^SUBLEVEL' "$DEST/kernel/Makefile" | tr '\n' ' '
echo
