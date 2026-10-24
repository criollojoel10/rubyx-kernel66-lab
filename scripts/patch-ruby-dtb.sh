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

# 7. scpsys: el nodo power-controller@10006000 del DTS stock matchea el driver
#    antiguo ("mediatek,mt6877-scpsys", nombre "clk-mt6877-scpsys" en el kernel
#    stock). En el arbol 6.6 del A34 ese mismo driver se llama
#    "clk-mt6877-scpsys-clk" y matchea "mediatek,mt6877-scpsys-clk", asi que
#    sin este compatible NADIE registra el proveedor de relojes del nodo.
#    Consecuencia en v27: devm_clk_get(dev, "power") falla en mtk-smi-common y
#    en todos los larb (CLK0:power get failed) -> SMI no sondea -> mtk_iommu
#    no encuentra smicommon_node phase1 (-22) -> sin display.
#    "syscon" no lo reclama el driver syscon del GKI (solo casa por id de
#    plataforma "syscon"), y "simple-mfd" solo hace populate de los hijos, asi
#    que el modulo clk puede enlazar el nodo sin pelearse con nadie.
fdtput -t s "$D" /power-controller@10006000 compatible \
  "mediatek,mt6877-scpsys-clk" "mediatek,mt6877-scpsys" "syscon" "simple-mfd"

# 8. SMI/IOMMU: el DTS stock de ruby (4.19) expresa el enlace larb -> smi_common
#    con "mediatek,smi = <phandle>". El driver 6.6 (mtk-smi.c) y el iommu
#    (mtk_iommu.c) leen "mediatek,smi-supply" con of_parse_phandle_with_fixed_args
#    (phandle + 1 arg = is_pwr_decp). Sin esto:
#      - mtk_smi_larb_probe() no enlaza smi_common (smi_common_dev[0] = NULL).
#      - mtk_iommu_probe() devuelve -EINVAL en "can't find smicomm_node phase1"
#        (lee smi-supply del ultimo larb = smi_larb20) -> m4u@14016000 no sondea.
#      - Sin iommu, ovl/rdma/postmask (iommus=<&m4u ...>) difieren -110.
SMI=$(fdtget -t x "$D" /smi_common@14002000 phandle)
for L in \
  smi_larb0@14003000 smi_larb1@14004000 smi_larb2@1f002000 smi_larb4@1602e000 \
  smi_larb7@17010000 smi_larb9@1502e000 smi_larb11@1582e000 smi_larb13@1a001000 \
  smi_larb14@1a002000 smi_larb16@1a00f000 smi_larb17@1a010000 smi_larb18@1a011000 \
  smi_larb19@1b10f000 smi_larb20@1b00f000; do
  fdtput -t x "$D" "/$L" mediatek,smi-supply "$SMI" 0x0
done

# 8b. IOMMU: m4u@14016000 (mt6877_data_iommu0, flag IOMMU_SEC_EN) lee
#     "mediatek,iommu_banks" para los bancos seguros 1..3. Sin la propiedad el
#     probe solo salta el setup de IRQ de banco (no fatal), pero la anadimos
#     para no perderlos. Cada banco necesita "mediatek,bank-id".
B1=$(fdtget -t x "$D" /m4u@14017000 phandle)
B2=$(fdtget -t x "$D" /m4u@14018000 phandle)
B3=$(fdtget -t x "$D" /m4u@14019000 phandle)
fdtput -t x "$D" /m4u@14016000 mediatek,iommu_banks "$B1" "$B2" "$B3"
fdtput -t x "$D" /m4u@14017000 mediatek,bank-id 0x1
fdtput -t x "$D" /m4u@14018000 mediatek,bank-id 0x2
fdtput -t x "$D" /m4u@14019000 mediatek,bank-id 0x3

# 8c. Larbs de camara (13/14/16/17/18) llevan "power-domains = <0x71 N>" (cam_pd,
#     compatible "mediatek,mt6877-camera-power-controller"). Ningun driver de
#     este arbol registra ese genpd, asi que dev_pm_domain_attach() difiere esos
#     larbs para siempre -> su component_add() nunca corre -> el component
#     master del iommu (que matchea los 14 larbs de "mediatek,larbs") nunca
#     enlaza -> sin config de puertos M4U para display. Quitamos power-domains:
#     la camara no funciona de todos modos.
for L in smi_larb13@1a001000 smi_larb14@1a002000 smi_larb16@1a00f000 \
         smi_larb17@1a010000 smi_larb18@1a011000; do
  fdtput -d "$D" "/$L" power-domains 2>/dev/null || true
done

# 8d. OVL 2L: el DTB stock de ruby usa "mediatek,mt6877-disp-ovl-2l" para
#     disp_ovl0_2l y disp_ovl1_2l, pero el driver 6.6 (mtk_disp_ovl.c) solo
#     matchea "mediatek,mt6877-disp-ovl" y distingue el 2L por el alias
#     (ovl3/ovl4). Sin esto esos dos componentes no se enlazan: mtk_drm_crtc_create
#     aborta "component 31 (OVL0_2L) disabled or missing" en main/minor y
#     "component 32 (OVL1_2L)" en third -> no se crea ningun crtc ->
#     private->crtc[0]=NULL -> panic en mtk_drm_top_clk_disable_unprepare.
fdtput -t s "$D" /disp_ovl0_2l@14006000 compatible \
  mediatek,disp_ovl0_2l mediatek,mt6877-disp-ovl
fdtput -t s "$D" /disp_ovl1_2l@1401f000 compatible \
  mediatek,disp_ovl1_2l mediatek,mt6877-disp-ovl

# 9. UFS: sin el regulador microtrust registrado, el probe de UFS devuelve -517.
if [ "$KEEP_VCC" = "0" ]; then
  fdtput -d "$D" /ufshci@11270000 vcc-supply 2>/dev/null || true
fi

echo "[dtb] DTB parcheado: $OUT"
fdtget -t x "$D" /pinctrl mediatek,eint >/dev/null
fdtget -t x "$D" /eint@1000b000 interrupts
