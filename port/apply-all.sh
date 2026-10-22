#!/usr/bin/env bash
# Aplica TODOS los ports de ruby al arbol 6.6 (kernel de producto).
#
#   display : panel m16 36-02-0b (mediatek_v2)
#   touch   : Focaltech FT3680 por SPI3
#   charger : mp2762, ln8410, bq25980, sc8561, max77932, xmusb350
#   tee     : Microtrust TEEI 400 (el TEE real de ruby)
#
# Los drivers de display/input/power se compilan desde el GKI
# (sources/a34x/kernel-6.6); el TEE, desde los device modules.
#
# Uso: ./port/apply-all.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${1:-}" ]; then
  GKI="$1/kernel-6.6"
  DM="$1/kernel/kernel_device_modules-6.6"
else
  GKI="sources/a34x/kernel-6.6"
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

[ -d "$GKI/drivers/gpu/drm/panel" ] || { echo "falta $GKI" >&2; exit 1; }
[ -d "$DM/drivers/tee/teei" ] || { echo "falta $DM" >&2; exit 1; }

echo "== display (panel m16)"
./port/display/apply.sh "$GKI"

echo "== touch (Focaltech FT3680)"
./port/touch/apply.sh "$GKI"

echo "== charger (drivers de Xiaomi)"
./port/charger/apply.sh "$GKI"

echo "== tee (Microtrust TEEI 400)"
./scripts/patch-mtk-tee-config.sh

echo "== config (fragmento combinado)"
./scripts/apply-ruby-fragment.sh configs/ruby-6.6/full.fragment

echo "== modulos declarados en Kleaf"
./scripts/patch-kleaf-outs.py --gki \
  drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.ko \
  drivers/input/touchscreen/focaltech_3680/focaltech_3680.ko \
  drivers/power/supply/mps/mp2762.ko \
  drivers/power/supply/ln/ln8410.ko \
  drivers/power/supply/ti/bq25980.ko \
  drivers/power/supply/southchip/sc8561.ko \
  drivers/power/supply/maxim/max77932.ko \
  drivers/power/supply/xiaomi/xmusb350.ko
./scripts/patch-kleaf-outs.py --dm drivers/tee/teei/400/isee.ko

echo "[apply-all] listo"
