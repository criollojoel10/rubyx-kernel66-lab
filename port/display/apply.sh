#!/usr/bin/env bash
# Aplica los paneles m16 de ruby al arbol 6.6 (API mediatek_v2).
#
# ruby tiene tres variantes de panel m16. El dtbo declara:
#   panel1@0 -> "m16_42_0d_0a_dsc_vdo,lcm"   (el activo: lo selecciona el
#                                               cmdline del kernel stock)
#   panel2@0 -> "m16_36_02_0b_dsc_vdo,lcm"
# y el 4.19 de ruby trae tambien el 45-02-0c.
#
# Los paneles se compilan como modulos (=m) desde el arbol de device
# modules, en el mismo build que mediatek-drm.ko: los CRCs de
# mtk_panel_ext_create/mtk_panel_ext_param_set solo cuadran si ambos salen
# del mismo artefacto.
#
# Uso: ./port/display/apply.sh [raiz/del/arbol-con-drivers/gpu/drm/panel]
set -euo pipefail
cd "$(dirname "$0")/../.."

PANELDIR="${1:-sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel}"
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
  python3 - "$K" "$sym" "Xiaomi m16 $p DSC VDO panel" "$p" <<'PY'
import sys
kconf, sym, title, p = sys.argv[1:5]
lines = open(kconf).read().splitlines()
out, skip = [], False
for l in lines:
    if l.startswith("config "):
        skip = (l.split()[1] == sym)
    if not skip:
        out.append(l)
out += [
    "",
    f"config {sym}",
    f'\ttristate "{title}"',
    "\tdepends on OF",
    "\tdepends on DRM_MIPI_DSI",
    "\tdepends on BACKLIGHT_CLASS_DEVICE",
    "\thelp",
    f"\t  Panel m16 {p} de ruby (1080x2400, DSC VDO). El DCS y los timings",
    "\t  salen del driver 4.19 de ruby (scripts/port-m16-panel.py).",
]
open(kconf, "w").write("\n".join(out) + "\n")
PY

  # obj-m incondicional: el .ko tiene que existir aunque el merge de Kleaf
  # vuelva a perder el simbolo. Reescribe cualquier linea previa para que
  # apply.sh sea idempotente.
  M="$PANELDIR/Makefile"
  python3 - "$M" "panel-m16-$p-dsc-vdo.o" <<'PY'
import sys
p, obj = sys.argv[1], sys.argv[2]
lines = [l for l in open(p).read().splitlines() if obj not in l]
lines.append("obj-m += " + obj)
open(p, "w").write("\n".join(lines) + "\n")
PY
  echo "[display] panel m16 $p aplicado"
done

echo "[display] paneles aplicados en $PANELDIR"
