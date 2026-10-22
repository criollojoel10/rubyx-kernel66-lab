#!/usr/bin/env bash
# Aplica TODOS los ports de ruby al arbol 6.6 (kernel de producto).
#
#   display : panel m16 42-0d-0a (mediatek_v2)  -> port/display (GKI)
#   touch   : Focaltech FT3680 por SPI3           -> port/touch   (GKI)
#   huella  : Goodix SPI (UUID de la TA Goodix)    -> port/fingerprint (GKI)
#   tee     : Microtrust TEEI 400 + mediatek_v2   -> port/mtk-drivers (GKI)
#   carga   : la hace el cargador del PMIC mt6360, que el A34 ya trae
#
# Los drivers de display/input/power se compilan desde el GKI
# (sources/a34x/kernel-6.6); el TEE y la mediatek_v2 viven en los device
# modules, que no se compilan por si solos (ALLOW_BUILTIN=n), asi que se
# copian al GKI.
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

echo "== display: panel m16 42-0d-0a (el A34 no lo trae)"
./port/display/apply.sh "$GKI"

echo "== touch: Focaltech FT3680 por SPI3 (el A34 no lo trae)"
./port/touch/apply.sh "$GKI"

echo "== huella: Goodix SPI (el A34 no lo trae)"
./port/fingerprint/apply.sh "$GKI"

echo "== parche del GKI: /vendor/firmware en fw_path[]"
./port/kernel-patches/firmware-path.sh "$GKI"

echo "== TEEI 400 y mediatek_v2 (vienen de los device modules)"
./port/mtk-drivers/apply.sh "${1:-sources/a34x}"

echo "== carga: el cargador del PMIC mt6360 ya esta en el A34 (no hay nada que portar)"

echo "== tee (overlay de Microtrust TEEI 400)"
./scripts/patch-mtk-tee-config.sh

echo "== config (fragmento combinado)"
FRAG="${RUBY_FRAGMENT:-configs/ruby-6.6/full.fragment}"
./scripts/apply-ruby-fragment.sh "$FRAG"

echo "== lista de Kleaf sin los .ko de TEEGRIS (el TEE de ruby va built-in)"
./scripts/patch-kleaf-tee-builtin.py "${1:-sources/a34x}"

# El panel, el tactil y el TEE van BUILT-IN (=y), igual que en el kernel stock
# de ruby: no producen .ko y no hay que declararlos en las listas de Kleaf.
# (La lista de device modules ya queda sin los .ko de TEEGRIS, que es lo que
# hace patch-kleaf-tee-builtin.py.)

echo "[apply-all] listo"
