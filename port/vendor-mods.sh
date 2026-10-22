#!/usr/bin/env bash
# Prepara los modulos de vendor de MTK 6.6 (connectivity: GPS/wifi/bt, GPU,
# camara) en el arbol de A34, que es donde el build los espera
# (build.config.mtk_kernel_device_modules -> EXT_MODULES con rutas
# ../vendor/mediatek/kernel_modules/...).
#
# Uso: ./port/vendor-mods.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="${1:-sources/a34x}"
SRC="$ROOT/kernel/kernel_device_modules-6.6"
DST="$ROOT/vendor/mediatek/kernel_modules"
REPO="https://github.com/HelloVolla/android_kernel_modules_volla_mt6877.git"
REF="volla-16.0"

[ -d "$SRC" ] || { echo "falta $SRC; ejecuta make fetch" >&2; exit 1; }

if [ ! -d "$DST/.git" ]; then
  mkdir -p "$(dirname "$DST")"
  echo "[vendor-mods] clonando $REPO @ $REF (~450 MB)"
  git clone --depth 1 --branch "$REF" "$REPO" "$DST"
else
  echo "[vendor-mods] ya esta en $DST"
fi

# ktf_testcase no viene en el repo publico y romperia el build.
BC="$SRC/build.config.mtk_kernel_device_modules"
if [ -f "$BC" ]; then
  sed -i '\|../vendor/mediatek/tests/kernel/ktf_testcase|d' "$BC"
fi

echo "[vendor-mods] listo"
for d in connectivity/gps/gps_stp connectivity/gps/data_link \
         connectivity/gps/gps_pwr connectivity/gps/gps_scp gpu mtkcam; do
  [ -d "$DST/$d" ] && echo "   OK $d"
done
