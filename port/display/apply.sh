#!/usr/bin/env bash
# Aplica el panel m16 de ruby al árbol 6.6 (mediatek_v2) del A34.
# Uso: ./port/display/apply.sh /ruta/a/kernel_device_modules-6.6
set -euo pipefail
cd "$(dirname "$0")/../.."

DM="${1:-sources/a34x/kernel-6.6}"
[ -d "$DM/drivers/gpu/drm/panel" ] || { echo "no existe $DM/drivers/gpu/drm/panel" >&2; exit 1; }

SRC="port/display/panel-m16-36-02-0b-dsc-vdo.c"
[ -f "$SRC" ] || { echo "falta $SRC (panel todavia no portado)" >&2; exit 1; }

cp "$SRC" "$DM/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c"
mkdir -p "$DM/drivers/gpu/drm/panel/include"
cp "port/display/include/panel-m16-36-02-0b-dsc-vdo.h" \
   "$DM/drivers/gpu/drm/panel/include/panel-m16-36-02-0b-dsc-vdo.h"
cp "port/display/m16-36-02-0b-init.inc" \
   "$DM/drivers/gpu/drm/panel/m16-36-02-0b-init.inc"

# Los drivers de display/input/power se compilan desde el GKI (en los device
# modules no hay Makefiles intermedios), asi que el simbolo va en el Kconfig
# del GKI.
K="$DM/drivers/gpu/drm/panel/Kconfig"
if ! grep -q '^config DRM_PANEL_M16_36_02_0B_DSC_VDO' "$K"; then
  cat >> "$K" <<'EOF'

# --- ruby: panel m16 36-02-0b (DSC VDO 1080x2400) ---
config DRM_PANEL_M16_36_02_0B_DSC_VDO
	tristate "Xiaomi m16 36-02-0b DSC VDO panel"
	depends on OF
	depends on DRM_MIPI_DSI
	depends on BACKLIGHT_CLASS_DEVICE
	depends on DRM_MEDIATEK_V2
	help
	  Xiaomi m16 36-02-0b panel (1080x2400, DSC VDO) ported from
	  ruby 4.19 to mediatek_v2.
EOF
fi

M="$DM/drivers/gpu/drm/panel/Makefile"
if ! grep -q 'panel-m16-36-02-0b-dsc-vdo.o' "$M"; then
  echo 'obj-$(CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO) += panel-m16-36-02-0b-dsc-vdo.o' >> "$M"
fi

./scripts/apply-ruby-fragment.sh configs/ruby-6.6/panel.fragment

echo "[display] panel m16 36-02-0b aplicado en $DM"
