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
[ -f "$MODTAR" ] || { echo "no encuentro $MODTAR" >&2; exit 1; }

# 2) modulos de ruby
MODDIR="artifacts/ruby-mods"
rm -rf "$MODDIR"; mkdir -p "$MODDIR"
echo "[boot] extrayendo modulos de ruby de $MODTAR"
tar --zstd -xf "$MODTAR" -C "$MODDIR"

MODS=$(cd "$MODDIR" && find . -name '*.ko' | sed 's|^\./||' | grep -E \
  'drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo\.ko|drivers/input/touchscreen/focaltech_3680/focaltech_3680\.ko|drivers/power/supply/(mps/mp2762|ln/ln8410|ti/bq25980|southchip/sc8561|maxim/max77932|xiaomi/xmusb350)\.ko|drivers/tee/teei/400/isee\.ko' \
  | sort)
if [ -z "$MODS" ]; then
  echo "[boot] AVISO: el artefacto no contiene modulos de ruby" >&2
else
  echo "$MODS" | sed 's/^/   /'
fi

# modules.load: orden de carga (TEE antes que el resto)
ORDER=""
for m in drivers/tee/teei/400/isee.ko \
         drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.ko \
         drivers/input/touchscreen/focaltech_3680/focaltech_3680.ko \
         drivers/power/supply/mps/mp2762.ko \
         drivers/power/supply/ln/ln8410.ko \
         drivers/power/supply/ti/bq25980.ko \
         drivers/power/supply/southchip/sc8561.ko \
         drivers/power/supply/maxim/max77932.ko \
         drivers/power/supply/xiaomi/xmusb350.ko; do
  case "$MODS" in *"$m"*) ORDER="$ORDER$m
";; esac
done
printf '%s' "$ORDER" > "$MODDIR/modules.load"
echo "[boot] modules.load: $(wc -l < "$MODDIR/modules.load") modulos"

# 3) ramdisk con los modulos
UNPACKED="/root/ruby-gki/work/boot_unpacked"
[ -d "$UNPACKED" ] || UNPACKED="work/boot_unpacked"
RAMDISK_LZ4="artifacts/ramdisk-ruby.lz4"
./scripts/pack-ramdisk-modules.sh "$UNPACKED" "$MODDIR" "$RAMDISK_LZ4"

# 4) boot.img
DTB="dts/ruby-stock-base.dtb"
[ -f "$DTB" ] || DTB="/root/ruby-gki/work/dtb_boot/01_dtbdump_MT6877.dtb"
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
