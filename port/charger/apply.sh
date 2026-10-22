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

# subdir:simbolo:descripcion
DIRS="mps:RUBY_MP2762:mp2762 charger"
DIRS="$DIRS ln:RUBY_LN8410:ln8410 charger"
DIRS="$DIRS ti:RUBY_BQ25980:bq25980 charger"
DIRS="$DIRS southchip:RUBY_SC8561:sc8561 charger"
DIRS="$DIRS maxim:RUBY_MAX77932:max77932 charger"
DIRS="$DIRS xiaomi:RUBY_XMUSB350:xmusb350 USB-PD"

M="$PS/Makefile"
# Los simbolos van en el Kconfig.ext de los device modules: es el fichero que
# SI se sourcea siempre en el build (anadirlos al Kconfig del subdirectorio
# no llegaba al arbol de configuracion).
KEXT="$DM/Kconfig.ext"

for pair in $DIRS; do
  d="${pair%%:*}"
  rest="${pair#*:}"
  sym="${rest%%:*}"
  desc="${rest#*:}"
  [ -d "$SRC/$d" ] || continue

  rm -rf "$PS/$d"
  cp -a "$SRC/$d" "$PS/$d"
  # Los simbolos se declaran en el Kconfig.ext de los device modules; aqui
  # solo queda un Kconfig de cortesia (sin definir el simbolo).
  cat > "$PS/$d/Kconfig" <<EOF
# El simbolo $sym se declara en el Kconfig.ext de los device modules
# (ver port/charger/apply.sh).
EOF
  # charger_class.h (framework MTK) vive un nivel arriba
  sed -i '1i ccflags-y += -I$(srctree)/$(src)/..' "$PS/$d/Makefile"

  append() {
    local file="$1" line="$2"
    [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ] && echo >> "$file"
    printf '%s\n' "$line" >> "$file"
  }

  grep -q "^config $sym" "$KEXT" || {
    {
      echo
      echo "# --- ruby: driver de carga $desc ---"
      echo "config $sym"
      echo "	tristate \"$desc\""
      echo "	help"
      echo "	  Driver de carga de Xiaomi ruby portado desde el 4.19."
    } >> "$KEXT"
  }

  grep -q "CONFIG_$sym) += $d/" "$M" ||
    append "$M" "obj-\$(CONFIG_$sym) += $d/"
done

./scripts/apply-ruby-fragment.sh configs/ruby-6.6/charger.fragment "$DM"

echo "[charger] drivers de carga de ruby aplicados en $PS"
grep -E 'RUBY_' "$M" || true
