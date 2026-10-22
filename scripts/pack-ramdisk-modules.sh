#!/usr/bin/env bash
# Inserta el cierre de módulos en el ramdisk stock de ruby.
# Uso: ./scripts/pack-ramdisk-modules.sh <boot_unpacked> <moddir> <salida.lz4>
set -euo pipefail
cd "$(dirname "$0")/.."

UNPACKED="$(realpath -m "${1:?falta boot_unpacked}")"
MODDIR="$(realpath -m "${2:?falta directorio de módulos}")"
OUT="$(realpath -m "${3:?falta salida del ramdisk}")"

[ -f "$UNPACKED/ramdisk" ] || { echo "falta $UNPACKED/ramdisk" >&2; exit 1; }
[ -f "$MODDIR/modules.load" ] || { echo "falta $MODDIR/modules.load" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

lz4 -d -f "$UNPACKED/ramdisk" "$TMP/ramdisk.cpio" >/dev/null
mkdir -p "$TMP/root"
(
  cd "$TMP/root"
  cpio -idm < "$TMP/ramdisk.cpio" 2>/dev/null
  mkdir -p lib/modules
  cp "$MODDIR"/*.ko "$MODDIR/modules.load" lib/modules/

  # Wrapper de primera etapa: carga los modulos de ruby y arma un watchdog
  # que devuelve al slot A si Android no arranca (solo para imagenes de test).
  if [ -f port/device/selfheal/first-stage-init.sh ]; then
    [ -e init ] && mv init init.ramdisk
    cp port/device/selfheal/first-stage-init.sh init
    chmod 755 init
    echo "  (init de primera etapa con watchdog instalado)"
  fi
  if [ -f port/device/selfheal/bctool ]; then
    cp port/device/selfheal/bctool bctool
    chmod 755 bctool
  fi

  find . -print0 | cpio --null -o -H newc > "$TMP/new.cpio" 2>/dev/null
)
lz4 -l -9 -f "$TMP/new.cpio" "$OUT" >/dev/null
lz4 -t "$OUT" >/dev/null
echo "ramdisk: $OUT ($(stat -c%s "$OUT") bytes, $(find "$MODDIR" -name '*.ko' | wc -l) módulos)"
