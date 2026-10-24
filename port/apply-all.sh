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

# Los paneles m16 van como MODULOS (=m) y se compilan en el arbol de device
# modules, junto a mediatek-drm.ko: los CRCs de mtk_panel_ext_* solo cuadran
# si los dos salen del mismo build. Por eso apply.sh apunta al arbol de
# device modules y hay que declararlos en mtk_device_modules (la lista que
# Kleaf compila de verdad).
echo "== display: paneles m16 (el A34 no los trae)"
./port/display/apply.sh "${1:+$1/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel}"
python3 scripts/patch-kleaf-outs.py \
  --dm drivers/gpu/drm/panel/panel-m16-42-0d-0a-dsc-vdo.ko \
  --dm drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.ko \
  --dm drivers/gpu/drm/panel/panel-m16-45-02-0c-dsc-vdo.ko

echo "== touch: Focaltech FT3680 por SPI3 (el A34 no lo trae)"
./port/touch/apply.sh "$GKI"

echo "== huella: Goodix SPI (el A34 no lo trae)"
./port/fingerprint/apply.sh "$GKI"

echo "== parche del GKI: /vendor/firmware en fw_path[]"
./port/kernel-patches/firmware-path.sh "$GKI"

echo "== TEEI 400 y mediatek_v2 (vienen de los device modules)"
./port/mtk-drivers/apply.sh "${1:-sources/a34x}"

echo "== carga: el cargador del PMIC mt6360 ya esta en el A34 (no hay nada que portar)"

echo "== audio: card MT6877 + altavoz aw882xx"
if [ -n "${1:-}" ]; then
  ./port/audio/apply-card.sh "$1"
else
  ./port/audio/apply-card.sh
fi

echo "== audio (altavoz aw882xx + vibrador aw8697)"
./port/audio/apply.sh "$GKI"

echo "== tee (overlay de Microtrust TEEI 400)"
./scripts/patch-mtk-tee-config.sh

echo "== samsung: sec_ext.ko sin el nodo sec_debug (el DTB de ruby no lo trae)"
./port/samsung/apply.sh "${1:-sources/a34x}"

echo "== clk: power-gates mtcmos (PG_DISP y demas) descomentados en clk-mt6877-pg.c"
# El DTB de ruby usa el nodo scpsys como proveedor de relojes (#clock-cells=1):
# los consumidores (mtk-smi-common/larb, mtk_iommu, mediatek-drm) hacen
# devm_clk_get(dev,"power") -> SCP_SYS_DISP. En el A34 esos PGATE estan
# comentados (el A34 mueve mtcmos a mtk-scpsys genpd), asi que "power" no
# existe y SMI falla con CLK0:power get failed. Se descomentan todos, igual
# que en el kernel stock de ruby.
./port/clk/apply.sh "${1:-sources/a34x}"

echo "== iommu: guard de m4u_data en mtk_iommu_port_idx (evita NULL deref del display)"
./port/iommu/apply.sh "${1:-sources/a34x}"

echo "== mfd: IRQ del PMIC mt6359p no fatal (sin celdas mt6359p-* el UFS queda -517)"
./port/mfd/apply.sh "${1:-sources/a34x}"

echo "== config (fragmento combinado)"
FRAG="${RUBY_FRAGMENT:-configs/ruby-6.6/full.fragment}"
./scripts/apply-ruby-fragment.sh "$FRAG"

echo "== lista de Kleaf sin los .ko de TEEGRIS (el TEE de ruby va built-in)"
./scripts/patch-kleaf-tee-builtin.py "${1:-sources/a34x}"

# El tactil y el TEE van BUILT-IN (=y), igual que en el kernel stock de ruby:
# no producen .ko. El panel SI es modulo (ver arriba).
# (La lista de device modules ya queda sin los .ko de TEEGRIS, que es lo que
# hace patch-kleaf-tee-builtin.py.)

echo "[apply-all] listo"
