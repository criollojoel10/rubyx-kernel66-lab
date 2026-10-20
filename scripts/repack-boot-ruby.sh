#!/usr/bin/env bash
# Reempaqueta boot.img de ruby con un kernel/DTB propios.
# Uso: ./scripts/repack-boot-ruby.sh <unpacked> <salida.img> [kernel] [dtb]
set -euo pipefail
cd "$(dirname "$0")/.."

UNPACKED="${1:?falta directorio desempaquetado}"
OUT="${2:?falta imagen de salida}"
KERNEL="${3:-$UNPACKED/kernel}"
DTB="${4:-$UNPACKED/dtb}"
RAMDISK="${5:-$UNPACKED/ramdisk}"
CMDLINE="${6:-bootopt=64S3,32N2,64N2 androidboot.tee_type=2}"

[ -f "$KERNEL" ] || { echo "falta kernel: $KERNEL" >&2; exit 1; }
[ -f "$RAMDISK" ] || { echo "falta ramdisk: $RAMDISK" >&2; exit 1; }
[ -f "$DTB" ] || { echo "falta dtb: $DTB" >&2; exit 1; }
command -v mkbootimg >/dev/null || { echo "falta mkbootimg" >&2; exit 1; }

mkbootimg \
  --kernel "$KERNEL" \
  --ramdisk "$RAMDISK" \
  --dtb "$DTB" \
  --header_version 2 \
  --pagesize 2048 \
  --base 0x40078000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x11088000 \
  --tags_offset 0x07c08000 \
  --dtb_offset 0x07c08000 \
  --cmdline "$CMDLINE" \
  --os_version 17.0.0 \
  --os_patch_level 2026-10 \
  --output "$OUT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unpack_bootimg --boot_img "$OUT" --out "$TMP" > "$TMP/header.txt"
grep -E 'kernel_size|ramdisk size|dtb size|header version|command line' "$TMP/header.txt"
echo "boot.img: $OUT"
