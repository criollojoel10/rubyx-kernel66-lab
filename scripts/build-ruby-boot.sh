#!/usr/bin/env bash
# Empaqueta un boot.img de ruby con NUESTRO kernel 6.6.
#
# Usa el ramdisk y el DTB del release (el DTB 6.6 de ruby ya esta extraido y
# se parchea con scripts/patch-ruby-dtb.sh) y sustituye el kernel.
#
# Uso:
#   scripts/build-ruby-boot.sh --kernel <Image.gz> [opciones]
#
#   --kernel FILE     kernel comprimido (Image.gz) que se mete en el boot.img
#   --modules DIR     directorio con los .ko + modules.load para el ramdisk
#   --modules-tar T   .tar.zst con los modulos (se extrae y se usa)
#   --out FILE        boot.img de salida (por defecto artifacts/boot-ruby-6.6.img)
#   --ruby-repo DIR   repo ruby-gki con work/boot_unpacked (por defecto /root/ruby-gki)
#   --no-dtb-patch    no parcheear el DTB
set -euo pipefail
cd "$(dirname "$0")/.."

KERNEL=""; MODULES=""; MODULES_TAR=""; OUT="artifacts/boot-ruby-6.6.img"
RUBY_REPO="/root/ruby-gki"; PATCH_DTB=1

while [ $# -gt 0 ]; do
  case "$1" in
    --kernel) KERNEL="$2"; shift 2;;
    --modules) MODULES="$2"; shift 2;;
    --modules-tar) MODULES_TAR="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --ruby-repo) RUBY_REPO="$2"; shift 2;;
    --no-dtb-patch) PATCH_DTB=0; shift;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) echo "opcion desconocida: $1" >&2; exit 2;;
  esac
done

[ -n "$KERNEL" ] || { echo "falta --kernel" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "no existe el kernel: $KERNEL" >&2; exit 1; }

UNPACKED="$RUBY_REPO/work/boot_unpacked"
[ -d "$UNPACKED" ] || { echo "no existe $UNPACKED (¿--ruby-repo?)" >&2; exit 1; }
[ -f "$UNPACKED/ramdisk" ] || { echo "falta el ramdisk stock en $UNPACKED" >&2; exit 1; }
DTBSRC="$RUBY_REPO/work/dtb_boot/01_dtbdump_MT6877.dtb"
[ -f "$DTBSRC" ] || { echo "falta el DTB stock: $DTBSRC" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) copia del ramdisk y del DTB stock
cp "$UNPACKED/ramdisk" "$TMP/ramdisk"
cp "$DTBSRC" "$TMP/dtb"

# 2) DTB parcheado (pinctrl/EINT/PMIC/reguladores/UFS)
if [ "$PATCH_DTB" = "1" ]; then
  ./scripts/patch-ruby-dtb.sh "$TMP/dtb" "$TMP/dtb.patched"
  mv "$TMP/dtb.patched" "$TMP/dtb"
  echo "[boot] DTB parcheado"
fi

# 3) modulos en el ramdisk
if [ -n "$MODULES_TAR" ]; then
  mkdir -p "$TMP/mods"
  tar --zstd -xf "$MODULES_TAR" -C "$TMP/mods"
  MODULES="$TMP/mods"
fi
if [ -n "$MODULES" ]; then
  [ -d "$MODULES" ] || { echo "no existe el directorio de modulos: $MODULES" >&2; exit 1; }
  ./scripts/pack-ramdisk-modules.sh "$UNPACKED" "$MODULES" "$TMP/ramdisk.new"
  mv "$TMP/ramdisk.new" "$TMP/ramdisk"
fi

# 4) empaquetado
./scripts/repack-boot-ruby.sh "$TMP" "$OUT" "$KERNEL" "$TMP/dtb" "$TMP/ramdisk"

sha256sum "$OUT" | tee "$OUT.sha256"
echo
echo "boot.img listo: $OUT"
echo "  kernel : $(stat -c%s "$KERNEL") bytes"
echo "  dtb    : $(stat -c%s "$TMP/dtb") bytes"
echo "  ramdisk: $(stat -c%s "$TMP/ramdisk") bytes"
