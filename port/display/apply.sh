#!/usr/bin/env bash
# Aplica el panel m16 42-0d-0a de ruby al arbol 6.6 (API mediatek_v2).
#
# El panel lo declara el cmdline del kernel stock de ruby:
#   panel-m16-42-0d-0a-dsc-vdo.oled_wp=...
# y el dtbo lo instancia como panel2@0 con "m16_42_0d_0a_dsc_vdo,lcm".
#
# Uso: ./port/display/apply.sh [raiz/del/arbol-con-drivers/gpu/drm/panel]
set -euo pipefail
cd "$(dirname "$0")/../.."

PANELDIR="${1:-sources/a34x/kernel-6.6/drivers/gpu/drm/panel}"
[ -d "$PANELDIR" ] || { echo "no existe $PANELDIR" >&2; exit 1; }

SRC="port/display"
[ -f "$SRC/panel-m16-42-0d-0a-dsc-vdo.c" ] || {
  echo "falta el port; ejecuta scripts/port-m16-panel.py" >&2; exit 1; }

cp "$SRC/panel-m16-42-0d-0a-dsc-vdo.c" "$PANELDIR/"
cp "$SRC/m16-42-0d-0a-init.inc"      "$PANELDIR/"
mkdir -p "$PANELDIR/include"
cp "$SRC/include/panel-m16-42-0d-0a-dsc-vdo.h" "$PANELDIR/include/"

K="$PANELDIR/Kconfig"
if ! grep -q '^config DRM_PANEL_M16_42_0D_0A_DSC_VDO' "$K"; then
  cat >> "$K" <<'EOF'

config DRM_PANEL_M16_42_0D_0A_DSC_VDO
	tristate "Xiaomi m16 42-0d-0a DSC VDO panel"
	depends on DRM_MEDIATEK_V2
	help
	  Panel m16 42-0d-0a de ruby (1080x2400, DSC VDO). El DCS sale del
	  driver 4.19 de ruby (scripts/port-m16-panel.py).
EOF
fi

M="$PANELDIR/Makefile"
if ! grep -q 'panel-m16-42-0d-0a-dsc-vdo.o' "$M"; then
  echo 'obj-$(CONFIG_DRM_PANEL_M16_42_0D_0A_DSC_VDO) += panel-m16-42-0d-0a-dsc-vdo.o' >> "$M"
fi

echo "[display] panel m16 42-0d-0a aplicado en $PANELDIR"
