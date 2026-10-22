#!/usr/bin/env bash
# Aplica al DTB stock de ruby los cambios que necesita el kernel 6.6 (A34).
# Reproducible: sustituye a los fdtput manuales.
#
# Uso: scripts/patch-ruby-dtb.sh <dtb_entrada> <dtb_salida> [--keep-vcc]
set -euo pipefail
cd "$(dirname "$0")/.."

IN="${1:?dtb de entrada}"
OUT="${2:?dtb de salida}"
KEEP_VCC=0
[ "${3:-}" = "--keep-vcc" ] && KEEP_VCC=1

cp "$IN" "$OUT"
D="$OUT"

# 1. pinctrl: el driver 6.6 exige reg + reg-names (9 bases), no reg_bases.
fdtput -t x "$D" /pinctrl reg \
  0x0 0x10005000 0x0 0x1000 \
  0x0 0x11c20000 0x0 0x1000 \
  0x0 0x11c30000 0x0 0x1000 \
  0x0 0x11d10000 0x0 0x1000 \
  0x0 0x11d30000 0x0 0x1000 \
  0x0 0x11d40000 0x0 0x1000 \
  0x0 0x11e20000 0x0 0x1000 \
  0x0 0x11ea0000 0x0 0x1000 \
  0x0 0x11f30000 0x0 0x1000
fdtput -t s "$D" /pinctrl reg-names \
  gpio iocfg_rm iocfg_rb iocfg_bm iocfg_bl iocfg_br iocfg_lm iocfg_rt iocfg_tl

# 2. EINT: el driver 6.6 lo busca por phandle desde pinctrl.
fdtput -t x "$D" /pinctrl mediatek,eint 0x48

# 3. Nodo eint: propiedades que exige mtk_eint_do_init() en 6.6.
fdtput -t s "$D" /eint@1000b000 reg-name eint
fdtput -t x "$D" /eint@1000b000 mediatek,total-pin-number 0x80
fdtput -t x "$D" /eint@1000b000 mediatek,instance-num 1
fdtput -t x "$D" /eint@1000b000 interrupts 0x0 0x100 0x4
fdtput -t x "$D" /eint@1000b000 interrupt-parent 0x1

# 4. PMIC: el MFD mt6397 de 6.6 matchea "mediatek,mt6359p".
fdtput -t s "$D" /pwrap@10026000/mt6359-pmic compatible \
  "mediatek,mt6359-pmic" "mediatek,mt6359p"

# 5. Reguladores: el driver 6.6 busca "ldo-vemc"/"ldo-vufs" (con guion).
fdtput -t s "$D" /pwrap@10026000/mt6359-pmic/mt6359regulator/ldo_vemc \
  regulator-compatible ldo-vemc
fdtput -t s "$D" /pwrap@10026000/mt6359-pmic/mt6359regulator/ldo_vufs \
  regulator-compatible ldo-vufs

# 6. UFS: sin el regulador microtrust registrado, el probe de UFS devuelve -517.
if [ "$KEEP_VCC" = "0" ]; then
  fdtput -d "$D" /ufshci@11270000 vcc-supply 2>/dev/null || true
fi

echo "[dtb] DTB parcheado: $OUT"
fdtget -t x "$D" /pinctrl mediatek,eint >/dev/null
fdtget -t x "$D" /eint@1000b000 interrupts
