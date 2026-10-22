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

# El GKI del A34 (mismo SoC MT6877, mismo panel m16) YA trae portados a 6.6
# el panel m16 36-02-0b y el tactil Focaltech FT3680:
#   kernel-6.6/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c
#   kernel-6.6/drivers/input/touchscreen/focaltech_3680/
# con los compatibles que usa el dtbo de ruby ("m16_36_02_0b_dsc_vdo,lcm" y
# "focaltech,3680-spi"). Solo hay que activarlos en el config.
echo "== drivers de MTK que ruby necesita (TEEI 400 y mediatek_v2)"
./port/mtk-drivers/apply.sh "${1:-sources/a34x}"

echo "== display y touch: drivers del GKI (ya portados por el A34)"

echo "== charger (drivers de Xiaomi, hay que portarlos)"
./port/charger/apply.sh "$DM"

echo "== tee (Microtrust TEEI 400)"
./scripts/patch-mtk-tee-config.sh

echo "== config (fragmento combinado)"
FRAG="${RUBY_FRAGMENT:-configs/ruby-6.6/full.fragment}"
./scripts/apply-ruby-fragment.sh "$FRAG"

echo "== lista de Kleaf sin los .ko de TEEGRIS (el TEE va built-in)"
./scripts/patch-kleaf-tee-builtin.py "${1:-sources/a34x}"

echo "== modulos declarados en Kleaf"
# El panel y el tactil van built-in (=y) como en el kernel stock de ruby, asi
# que no producen .ko. Los cargadores y el TEE si son modulos.
./scripts/patch-kleaf-outs.py --dm \
  drivers/power/supply/mps/mp2762.ko \
  drivers/power/supply/ln/ln8410.ko \
  drivers/power/supply/ti/bq25980.ko \
  drivers/power/supply/southchip/sc8561.ko \
  drivers/power/supply/maxim/max77932.ko \
  drivers/power/supply/xiaomi/xmusb350.ko \
  drivers/tee/teei/400/isee.ko

echo "[apply-all] listo"
