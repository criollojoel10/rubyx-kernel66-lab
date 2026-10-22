#!/usr/bin/env bash
# Aplica un fragmento de config al overlay de los device modules.
#
# Por que no basta con RUBY_OVERLAY: el build de A34 declara los overlays
# de los device modules en la llamada a gen_build_config.py, pero el fragmento
# que se copia a kernel/configs/ruby_overlay.config no llega al .config que
# compila los modulos (el simbolo queda como "not set" y el modulo no se
# construye). En cambio, editar directamente el overlay de MTK
# (mt6877_overlay.config) si funciona: es lo que hace el parche de Microtrust.
#
# El bloque del fragment se reescribe siempre (no solo la primera vez) y los
# simbolos que deje de usar un fragment se limpian del resto del fichero.
#
# Uso: scripts/apply-ruby-fragment.sh <fragment.config> [overlay.config]
set -euo pipefail
cd "$(dirname "$0")/.."

FRAG="${1:?falta el fragment}"
# Los overlays, el defconfig y sign.config SIEMPRE viven en los device
# modules: es el arbol cuyo .config compila tanto el GKI como los modulos.
DM="${RUBY_CONFIG_TREE:-sources/a34x/kernel/kernel_device_modules-6.6}"
OVERLAY="${2:-$DM/kernel/configs/mt6877_overlay.config}"

[ -f "$FRAG" ] || { echo "no existe el fragmento: $FRAG" >&2; exit 1; }
[ -f "$OVERLAY" ] || { echo "no existe el overlay: $OVERLAY (¿make fetch?)" >&2; exit 1; }

MARK="# --- ruby: $(basename "$FRAG") ---"
# simbolos que define el fragment (sin comentarios ni lineas vacias)
SYMS=$(grep -oE '^CONFIG_[A-Za-z0-9_]+' "$FRAG" | sort -u || true)
LINES=$(grep -vE '^\s*#\s*CONFIG_.*is not set\s*$' "$FRAG" | grep -vE '^\s*$' || true)

# reescribe el bloque identificado por $MARK en el fichero indicado
set_block() {
  local file="$1" mark="$2" lines="$3"
  [ -f "$file" ] || return 0

  # 1) simbolos del bloque anterior (para limpiarlos del resto del fichero)
  local prev
  # Solo las lineas del bloque anterior: si se imprimiese el fichero entero,
  # el sed del paso 3 borraria TODAS las lineas CONFIG_...= del fichero
  # (incluida CONFIG_BUILD_CONFIG_FILE, que el build necesita).
  prev=$(awk -v mark="$mark" '
    $0 == mark { skip = 1; next }
    skip && /^# --- / { skip = 0; next }
    skip { print; next }
  ' "$file" | grep -oE '^CONFIG_[A-Za-z0-9_]+' | sort -u || true)

  # 2) fuera el bloque anterior (marcador + sus lineas)
  awk -v mark="$mark" '
    $0 == mark { skip = 1; next }
    skip && /^# --- / { skip = 0 }
    skip { next }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

  # 3) fuera del resto del fichero los simbolos del bloque anterior y los del
  #    fragment (sed no falla si no encuentra nada)
  local sym
  for sym in $prev $SYMS; do
    sed -i "/^${sym}=/d" "$file"
  done

  # 4) el bloque nuevo
  { echo; echo "$mark"; echo "$lines"; } >> "$file"
  echo "[cfg] $(basename "$file") <- $(basename "$FRAG")"
}

set_block "$OVERLAY" "$MARK" "$LINES"

# y tambien en el defconfig de los device modules: es la base del merge, asi
# que el valor llega aunque el overlay no se llegue a fusionar.
set_block "$DM/arch/arm64/configs/mediatek-bazel_defconfig" "$MARK" "$LINES"

# sign.config es el ULTIMO fragmento del merge, asi que lo que pongamos ahi
# gana sobre cualquier overlay (incluido el de TEEGRIS, que apaga Microtrust).
set_block "$DM/kernel/configs/sign.config" "$MARK" "$LINES"

# comprobacion: los simbolos del fragment tienen que estar en los tres sitios
for f in "$OVERLAY" "$DM/arch/arm64/configs/mediatek-bazel_defconfig" \
         "$DM/kernel/configs/sign.config"; do
  [ -f "$f" ] || continue
  for sym in $SYMS; do
    grep -q "^${sym}=" "$f" || {
      echo "[cfg] ERROR: $sym no quedo en $(basename "$f")" >&2
      exit 1
    }
  done
done
