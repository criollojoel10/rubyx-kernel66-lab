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
ALL_CELLS=0
for a in "$@"; do
  [ "$a" = "--keep-vcc" ] && KEEP_VCC=1
  [ "$a" = "--all-cells" ] && ALL_CELLS=1
done

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

# 4. PMIC: el MFD de MTK (modulo mt6397.ko) matchea "mediatek,mt6359p" y
#    crea las celdas mt6359p-* (regulator, etc.). El MFD builtin de GKI solo
#    matchea "mediatek,mt6359", asi que NO lo ponemos: queremos el modulo.
#    "mediatek,mt6359-pmic" se queda para mtk-pmic-wrap y el resto.
fdtput -t s "$D" /pwrap@10026000/mt6359-pmic compatible \
  "mediatek,mt6359p" "mediatek,mt6359-pmic"

# 4b. Celdas del PMIC: el MFD busca cada celda por su of_compatible dentro
#     del nodo pmic. El DTS stock usa los nombres viejos (mt6359-*), y las
#     celdas mt6359p-* no encuentran nodo: el device se crea con of_node=NULL
#     y mtk_pmic_keys_probe revienta (NULL deref) al leer sus propiedades.
#     Anadimos el compatible nuevo delante y conservamos el viejo.
# Solo "keys" por defecto: es la unica celda que revienta (NULL deref) sin
# nodo. Las demas se anaden con --all-cells, pero ojo: con nodo, sus drivers
# sondean de verdad y una de ellas cuelga el arranque (sin panic ni log).
if [ "$ALL_CELLS" = "1" ]; then
PMIC=/pwrap@10026000/mt6359-pmic
fdtput -t s "$D" $PMIC/accdet compatible \
  mediatek,mt6359p-accdet mediatek,mt6359-accdet
fdtput -t s "$D" $PMIC/keys compatible \
  mediatek,mt6359p-keys mediatek,mt6359-keys
fdtput -t s "$D" $PMIC/pmic_efuse compatible \
  mediatek,mt6359p-efuse mediatek,mt6359-efuse
fdtput -t s "$D" $PMIC/mt635x-auxadc compatible \
  mediatek,mt6359p-auxadc mediatek,mt6359-auxadc
fdtput -t s "$D" $PMIC/mt6359_rtc compatible \
  mediatek,mt6359p-rtc mediatek,mt6359-rtc
fdtput -t s "$D" $PMIC/pmic_lbat_service compatible \
  mediatek,mt6359p-lbat_service mediatek,mt6359-lbat_service
fi
fdtput -t s "$D" /pwrap@10026000/mt6359-pmic/keys compatible \
  mediatek,mt6359p-keys mediatek,mt6359-keys

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
