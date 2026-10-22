#!/usr/bin/env bash
# Aplica el driver del tactil de ruby (Focaltech FT3680 por SPI) al arbol 6.6.
#
# El simbolo de Kconfig se declara en el Kconfig.ext de los device modules
# (fichero que SI se sourcea siempre) y no en el Kconfig del subdirectorio:
# anadir un "source" al Kconfig del subdirectorio no llega al arbol de
# configuracion que usa el build.
#
# Uso: ./port/touch/apply.sh [ruta/a/kernel_device_modules-6.6]
set -euo pipefail
cd "$(dirname "$0")/../.."

DM="${1:-sources/a34x/kernel-6.6}"
TS="$DM/drivers/input/touchscreen"
[ -d "$TS" ] || { echo "no existe $TS" >&2; exit 1; }

SRC="port/touch/focaltech_3680"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta scripts/port-touch-focal3680.py" >&2; exit 1; }

rm -rf "$TS/focaltech_3680"
cp -a "$SRC" "$TS/focaltech_3680"
# El simbolo se declara en el Kconfig.ext de los device modules; aqui solo
# queda un Kconfig de cortesia (sin definir el simbolo, para no duplicarlo).
cat > "$TS/focaltech_3680/Kconfig" <<'EOF'
# El simbolo TOUCHSCREEN_FOCALTECH_3680 se declara en el Kconfig.ext de los
# device modules (ver port/touch/apply.sh).
EOF

K="$DM/drivers/input/touchscreen/Kconfig"
if ! grep -q '^config TOUCHSCREEN_FOCALTECH_3680' "$K"; then
  cat >> "$K" <<'EOF'

# --- ruby: tactil Focaltech FT3680 por SPI3 (port desde el 4.19) ---
config TOUCHSCREEN_FOCALTECH_3680
	tristate "Focaltech FT3680 touchscreen (SPI)"
	help
	  Driver del panel tactil Focaltech FT3680 que monta el
	  Xiaomi ruby (m16) sobre SPI3. Portado desde el 4.19.
EOF
fi

M="$TS/Makefile"
if ! grep -q 'focaltech_3680/' "$M"; then
  echo 'obj-$(CONFIG_TOUCHSCREEN_FOCALTECH_3680) += focaltech_3680/' >> "$M"
fi

./scripts/apply-ruby-fragment.sh configs/ruby-6.6/touch.fragment

echo "[touch] driver FT3680 aplicado en $TS/focaltech_3680"
grep -n 'TOUCHSCREEN_FOCALTECH_3680' "$K" | head -2
