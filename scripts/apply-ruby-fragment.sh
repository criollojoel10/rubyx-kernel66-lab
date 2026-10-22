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
# Uso: scripts/apply-ruby-fragment.sh <fragment.config> [overlay.config]
set -euo pipefail
cd "$(dirname "$0")/.."

FRAG="${1:?falta el fragmento}"
DM="${2:-sources/a34x/kernel/kernel_device_modules-6.6}"
OVERLAY="$DM/kernel/configs/mt6877_overlay.config"

[ -f "$FRAG" ] || { echo "no existe el fragmento: $FRAG" >&2; exit 1; }
[ -f "$OVERLAY" ] || { echo "no existe el overlay: $OVERLAY (¿make fetch?)" >&2; exit 1; }

MARK="# --- ruby: $(basename "$FRAG") ---"

# idempotente: si ya esta el marcador, se sale
if grep -qF "$MARK" "$OVERLAY"; then
  echo "[cfg] $(basename "$FRAG") ya aplicado en $(basename "$OVERLAY")"
  exit 0
fi

LINES="$(grep -vE '^\s*#\s*CONFIG_.*is not set\s*$' "$FRAG" | grep -vE '^\s*$')"

{
  echo
  echo "$MARK"
  echo "$LINES"
} >> "$OVERLAY"

# y tambien en el defconfig de los device modules: es la base del merge, asi
# que el valor llega aunque el overlay no se llegue a fusionar.
DEFCONFIG="$DM/arch/arm64/configs/mediatek-bazel_defconfig"
if [ -f "$DEFCONFIG" ]; then
  if ! grep -qF "$MARK" "$DEFCONFIG"; then
    {
      echo
      echo "$MARK"
      echo "$LINES"
    } >> "$DEFCONFIG"
    echo "[cfg] $(basename "$FRAG") -> $(basename "$DEFCONFIG")"
  fi
fi

echo "[cfg] $(basename "$FRAG") -> $(basename "$OVERLAY")"
