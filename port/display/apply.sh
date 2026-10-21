#!/usr/bin/env bash
# Aplica el panel m16 de ruby al árbol 6.6 (mediatek_v2) del A34.
# Uso: ./port/display/apply.sh /ruta/a/kernel_device_modules-6.6
set -euo pipefail
cd "$(dirname "$0")/../.."

DM="${1:-sources/a34x/kernel/kernel_device_modules-6.6}"
[ -d "$DM/drivers/gpu/drm/panel" ] || { echo "no existe $DM/drivers/gpu/drm/panel" >&2; exit 1; }

SRC="port/display/panel-m16-36-02-0b-dsc-vdo.c"
[ -f "$SRC" ] || { echo "falta $SRC (panel todavia no portado)" >&2; exit 1; }

cp "$SRC" "$DM/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c"

K="$DM/drivers/gpu/drm/panel/Kconfig"
if ! grep -q '^config DRM_PANEL_M16_36_02_0B_DSC_VDO' "$K"; then
  cat >> "$K" <<'EOF'

config DRM_PANEL_M16_36_02_0B_DSC_VDO
	tristate "Xiaomi m16 36-02-0b DSC VDO panel"
	depends on DRM_MEDIATEK
	help
	  Xiaomi m16 36-02-0b panel (1080x2400, DSC VDO) ported from
	  ruby 4.19 to mediatek_v2.
EOF
fi

M="$DM/drivers/gpu/drm/panel/Makefile"
if ! grep -q 'panel-m16-36-02-0b-dsc-vdo.o' "$M"; then
  echo 'obj-$(CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO) += panel-m16-36-02-0b-dsc-vdo.o' >> "$M"
fi

echo "[display] panel m16 36-02-0b aplicado en $DM"
