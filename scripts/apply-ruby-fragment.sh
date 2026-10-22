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
# El bloque se reescribe siempre (no solo la primera vez): asi, si cambia el
# valor de un simbolo del fragment, el overlay no se queda con el viejo.
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
LINES="$(grep -vE '^\s*#\s*CONFIG_.*is not set\s*$' "$FRAG" | grep -vE '^\s*$')"

# reescribe el bloque identificado por $MARK en el fichero indicado
set_block() {
  local file="$1" mark="$2" lines="$3"
  [ -f "$file" ] || return 0
  local tmp; tmp="$(mktemp)"
  # 1) fuera el bloque anterior (marcador + sus lineas hasta el siguiente
  #    marcador) y anota los simbolos que tenia, para limpiarlos tambien del
  #    resto del fichero (si un fragment cambia de simbolo, el viejo se queda
  #    si no se limpia explicitamente)
  local prev_syms
  prev_syms=$(awk -v mark="$mark" '
    $0 == mark { skip = 1; next }
    skip && /^# --- / { skip = 0 }
    skip { print; next }
    { print }
  ' "$file" | grep -oE '^CONFIG_[A-Za-z0-9_]+' | sort -u)
  awk -v mark="$mark" '
    $0 == mark { skip = 1; next }
    skip && /^# --- / { skip = 0 }
    skip { next }
    { print }
  ' "$file" > "$tmp"
  local psym
  for psym in $prev_syms; do
    # grep -v devuelve 1 si no queda nada: con set -e abortaria el script
    grep -v "^${psym}=" "$tmp" > "$tmp.2" || true
    mv "$tmp.2" "$tmp"
  done
  # 2) fuera los valores viejos de los simbolos del fragment (por si cambiaron)
  local sym
  for sym in $(printf '%s\n' "$lines" | grep -oE '^CONFIG_[A-Za-z0-9_]+' | sort -u); do
    grep -v "^${sym}=" "$tmp" > "$tmp.2" || true
    mv "$tmp.2" "$tmp"
  done
  # 3) el bloque nuevo
  { echo; echo "$mark"; echo "$lines"; } >> "$tmp"
  mv "$tmp" "$file"
  echo "[cfg] $(basename "$file") <- $(basename "$FRAG")"
}

set_block "$OVERLAY" "$MARK" "$LINES"

# y tambien en el defconfig de los device modules: es la base del merge, asi
# que el valor llega aunque el overlay no se llegue a fusionar.
set_block "$DM/arch/arm64/configs/mediatek-bazel_defconfig" "$MARK" "$LINES"

# sign.config es el ULTIMO fragmento del merge, asi que lo que pongamos ahi
# gana sobre cualquier overlay (incluido el de TEEGRIS, que apaga Microtrust).
set_block "$DM/kernel/configs/sign.config" "$MARK" "$LINES"

grep -E '^CONFIG_' "$OVERLAY" | tail -12
