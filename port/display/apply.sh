#!/usr/bin/env bash
# Aplica los paneles m16 de ruby al arbol 6.6 (API mediatek_v2).
#
# ruby tiene tres variantes de panel m16. El dtbo declara:
#   panel1@0 -> "m16_42_0d_0a_dsc_vdo,lcm"   (el activo: lo selecciona el
#                                               cmdline del kernel stock)
#   panel2@0 -> "m16_36_02_0b_dsc_vdo,lcm"
# y el 4.19 de ruby trae tambien el 45-02-0c.
#
# Uso: ./port/display/apply.sh [raiz/del/arbol-con-drivers/gpu/drm/panel]
set -euo pipefail
cd "$(dirname "$0")/../.."

PANELDIR="${1:-sources/a34x/kernel-6.6/drivers/gpu/drm/panel}"
[ -d "$PANELDIR" ] || { echo "no existe $PANELDIR" >&2; exit 1; }

SRC="port/display"

# panel:simbolo-de-kconfig
PANELES="36-02-0b:DRM_PANEL_M16_36_02_0B_DSC_VDO
42-0d-0a:DRM_PANEL_M16_42_0D_0A_DSC_VDO
45-02-0c:DRM_PANEL_M16_45_02_0C_DSC_VDO"

mkdir -p "$PANELDIR/include"

for par in $PANELES; do
  p="${par%%:*}"; sym="${par##*:}"
  [ -f "$SRC/panel-m16-$p-dsc-vdo.c" ] || {
    echo "falta el port de $p; ejecuta scripts/port-m16-panel.py" >&2; exit 1; }

  cp "$SRC/panel-m16-$p-dsc-vdo.c" "$PANELDIR/"
  cp "$SRC/m16-$p-init.inc"        "$PANELDIR/"
  cp "$SRC/include/panel-m16-$p-dsc-vdo.h" "$PANELDIR/include/"

  K="$PANELDIR/Kconfig"
  if ! grep -q "^config $sym" "$K"; then
    cat >> "$K" <<EOF

config $sym
	tristate "Xiaomi m16 $p DSC VDO panel"
	depends on DRM_MEDIATEK_V2
	help
	  Panel m16 $p de ruby (1080x2400, DSC VDO). El DCS y los timings
	  salen del driver 4.19 de ruby (scripts/port-m16-panel.py).
EOF
  fi

  M="$PANELDIR/Makefile"
  if ! grep -q "panel-m16-$p-dsc-vdo.o" "$M"; then
    echo "obj-\$(CONFIG_$sym) += panel-m16-$p-dsc-vdo.o" >> "$M"
  fi
  echo "[display] panel m16 $p aplicado"
done

echo "[display] paneles aplicados en $PANELDIR"
