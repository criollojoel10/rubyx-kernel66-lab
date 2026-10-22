#!/usr/bin/env bash
# Aplica los drivers de carga de ruby (mp2762, ln8410, bq25980, sc8561,
# max77932, xmusb350) portados desde el 4.19 al arbol 6.6.
# Uso: ./port/charger/apply.sh [ruta/a/kernel_device_modules-6.6]
set -euo pipefail
cd "$(dirname "$0")/../.."

DM="${1:-sources/a34x/kernel/kernel_device_modules-6.6}"
PS="$DM/drivers/power/supply"
[ -d "$PS" ] || { echo "no existe $PS" >&2; exit 1; }

SRC="port/charger/drivers"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta scripts/port-charger.py" >&2; exit 1; }

# subdir:simbolo
DIRS="mps:RUBY_MP2762 ln:RUBY_LN8410 ti:RUBY_BQ25980 southchip:RUBY_SC8561"
DIRS="$DIRS maxim:RUBY_MAX77932 xiaomi:RUBY_XMUSB350"

K="$PS/Kconfig"
M="$PS/Makefile"

for pair in $DIRS; do
  d="${pair%%:*}"
  sym="${pair##*:}"
  [ -d "$SRC/$d" ] || continue

  rm -rf "$PS/$d"
  cp -a "$SRC/$d" "$PS/$d"
  # charger_class.h (framework MTK) vive un nivel arriba
  sed -i '1i ccflags-y += -I$(srctree)/$(src)/..' "$PS/$d/Makefile"

  append() {
    local file="$1" line="$2"
    [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ] && echo >> "$file"
    printf '%s\n' "$line" >> "$file"
  }

  grep -q "drivers/power/supply/$d/Kconfig" "$K" ||
    append "$K" "source \"\$(KCONFIG_EXT_PREFIX)drivers/power/supply/$d/Kconfig\""

  grep -q "CONFIG_$sym) += $d/" "$M" ||
    append "$M" "obj-\$(CONFIG_$sym) += $d/"
done

echo "[charger] drivers de carga de ruby aplicados en $PS"
grep -E 'RUBY_' "$M" || true
