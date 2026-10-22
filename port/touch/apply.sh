#!/usr/bin/env bash
# Aplica el driver del tactil de ruby (Focaltech FT3680 por SPI) al arbol 6.6.
# Uso: ./port/touch/apply.sh [ruta/a/kernel_device_modules-6.6]
set -euo pipefail
cd "$(dirname "$0")/../.."

DM="${1:-sources/a34x/kernel/kernel_device_modules-6.6}"
TS="$DM/drivers/input/touchscreen"
[ -d "$TS" ] || { echo "no existe $TS" >&2; exit 1; }

SRC="port/touch/focaltech_3680"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta scripts/port-touch-focal3680.py" >&2; exit 1; }

rm -rf "$TS/focaltech_3680"
cp -a "$SRC" "$TS/focaltech_3680"

K="$TS/Kconfig"
if ! grep -q 'focaltech_3680/Kconfig' "$K"; then
  cat >> "$K" <<'EOF'
source "$(KCONFIG_EXT_PREFIX)drivers/input/touchscreen/focaltech_3680/Kconfig"
EOF
fi

M="$TS/Makefile"
if ! grep -q 'focaltech_3680/' "$M"; then
  echo 'obj-$(CONFIG_TOUCHSCREEN_FOCALTECH_3680) += focaltech_3680/' >> "$M"
fi

echo "[touch] driver FT3680 aplicado en $TS/focaltech_3680"
