#!/usr/bin/env bash
# Monta un boot.img de ruby con el kernel 6.6 de MTK y los modulos nuevos
# (panel m16, tactil FT3680, cargadores, isee.ko de Microtrust).
#
#   boot.img = kernel 6.6 (Image.gz) + ramdisk stock con los .ko + DTB de ruby
#
# Uso:
#   scripts/build-ruby-boot.sh --artifacts artifacts/a34-6.6.127 --out /tmp/ruby-6.6.img
#   scripts/build-ruby-boot.sh --ci-run 39722994655 --out /tmp/ruby-6.6.img
set -euo pipefail
cd "$(dirname "$0")/.."

ART=""
RUN=""
OUT="/tmp/ruby-6.6.img"
MODSETS="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --artifacts) ART="$2"; shift 2;;
    --ci-run)    RUN="$2"; shift 2;;
    --out)       OUT="$2"; shift 2;;
    --modules)   MODSETS="$2"; shift 2;;
    *) echo "opcion desconocida: $1" >&2; exit 1;;
  esac
done

[ -n "$ART" ] || [ -n "$RUN" ] || { echo "falta --artifacts o --ci-run" >&2; exit 1; }

# 1) artefactos del CI
if [ -n "$RUN" ]; then
  ART="artifacts/ci-$RUN"
  mkdir -p "$ART"
  export HOME=/root
  echo "[boot] descargando artefactos del run $RUN"
  gh run download -R criollojoel10/rubyx-kernel66-lab "$RUN" \
      -n "$(gh run view -R criollojoel10/rubyx-kernel66-lab "$RUN" --json artifacts \
            --jq '.artifacts[0].name')" -D "$ART" || true
  # el artefacto viene en artifacts/<nombre>/
  SUB="$(find "$ART" -maxdepth 2 -name 'a34-6.6.127' -type d | head -1)"
  [ -n "$SUB" ] && ART="$SUB"
fi

KERNEL="$ART/Image.gz"
[ -f "$KERNEL" ] || KERNEL="$ART/Image"
[ -f "$KERNEL" ] || { echo "no encuentro el kernel en $ART" >&2; exit 1; }
MODTAR="$ART/a34-all-modules.tar.zst"
# opcional: los drivers de ruby van built-in, el tar solo sirve como informe

# 2) modulos de ruby: los drivers de ruby (display, tactil, huella, TEE)
#    van built-in en el kernel, asi que aqui no hay nada que cargar. El
#    ramdisk solo lleva el init de primera etapa con el watchdog.
MODDIR="artifacts/ruby-mods"
rm -rf "$MODDIR"; mkdir -p "$MODDIR"
if [ -f "$MODTAR" ]; then
  echo "[boot] modulos del build (informativo)"
  tar --zstd -tf "$MODTAR" 2>/dev/null | grep -E 'panel-m16|focaltech_3680|goodix|isee' | head -8 | sed 's/^/   /' || true
fi
printf '' > "$MODDIR/modules.load"

# 3) ramdisk con los modulos
UNPACKED="/root/ruby-gki/work/boot_unpacked"
[ -d "$UNPACKED" ] || UNPACKED="work/boot_unpacked"
RAMDISK_LZ4="artifacts/ramdisk-ruby.lz4"
./scripts/pack-ramdisk-modules.sh "$UNPACKED" "$MODDIR" "$RAMDISK_LZ4"

# 4) boot.img
DTB="${RUBY_DTB:-/root/ruby-gki/work/dtb_boot/01_dtbdump_MT6877.dtb}"
[ -f "$DTB" ] || { echo "no encuentro el DTB de ruby: $DTB" >&2; exit 1; }
ORIG="device/backups/boot_b-stock.img"
[ -f "$ORIG" ] || ORIG="/root/ruby-gki/work/boot_b.img"

python3 scripts/build-diag-boot.py \
  --original "$ORIG" \
  --kernel "$KERNEL" \
  --initramfs "$RAMDISK_LZ4" \
  --dtb "$DTB" \
  --out "$OUT"

sha256sum "$OUT"
echo "[boot] listo: $OUT"
