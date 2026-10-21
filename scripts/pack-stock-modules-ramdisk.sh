#!/usr/bin/env bash
# Inyecta módulos en un ramdisk stock ya extraído y lo empaqueta en lz4.
# Uso: pack-stock-modules-ramdisk.sh <ramdisk_dir> <modules_dir> <out.lz4>
set -euo pipefail

RD="${1:?ramdisk dir}"
MODS="${2:?modules dir con .ko y modules.load}"
OUT="${3:?salida .lz4}"

[ -x "$RD/system/bin/init" ] || [ -e "$RD/init" ] || {
  echo "no parece un ramdisk Android: falta init" >&2
  exit 1
}
[ -f "$MODS/modules.load" ] || {
  echo "falta $MODS/modules.load" >&2
  exit 1
}

mkdir -p "$RD/lib/modules"
cp "$MODS"/*.ko "$RD/lib/modules/"
cp "$MODS/modules.load" "$RD/lib/modules/modules.load"

if [ -f "$MODS/modules.dep" ]; then
  cp "$MODS/modules.dep" "$RD/lib/modules/modules.dep"
fi

find "$RD" -print0 | cpio --null -o -H newc --quiet | lz4 -l -9 > "$OUT"
ls -lh "$OUT"
