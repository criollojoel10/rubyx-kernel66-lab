#!/usr/bin/env bash
# Añade "/vendor/firmware" a la lista fw_path[] del GKI 6.6.
#
# El kernel 4.19 de ruby busca el firmware en /vendor/firmware; el GKI 6.6 del
# A34 solo mira en /lib/firmware. Sin esta ruta, el firmware de MTK que vive
# en el vendor de ruby (conninfra, wlan, bt, aw882xx...) no se encuentra.
#
# Uso: ./port/kernel-patches/firmware-path.sh [raiz/del/gki]
set -euo pipefail
cd "$(dirname "$0")/../.."

GKI="${1:-sources/a34x/kernel-6.6}"
F="$GKI/drivers/base/firmware_loader/main.c"
[ -f "$F" ] || { echo "no existe $F" >&2; exit 1; }

if grep -q '"/vendor/firmware"' "$F"; then
  echo "[firmware-path] /vendor/firmware ya esta en fw_path[]"
  exit 0
fi

python3 - "$F" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

viejo = '''static const char * const fw_path[] = {
	fw_path_para[0],'''
nuevo = '''static const char * const fw_path[] = {
	/* ruby: el firmware de MTK vive en el vendor */
	"/vendor/firmware",
	fw_path_para[0],'''

if viejo not in text:
    sys.exit("no se encontro la lista fw_path[]")

with open(path, "w", encoding="utf-8") as f:
    f.write(text.replace(viejo, nuevo, 1))
print("[firmware-path] /vendor/firmware anadido a fw_path[]")
PY

grep -n -A 3 'static const char \* const fw_path' "$F" | head -6
