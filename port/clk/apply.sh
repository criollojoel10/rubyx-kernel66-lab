#!/usr/bin/env bash
# Restaura los power-gates (relojes mtcmos) que el clk-mt6877-pg.c del A34
# deja comentados en modo "bringup".
#
# El DTB stock de ruby tiene el nodo scpsys (power-controller@10006000) como
# proveedor de relojes (#clock-cells=1), y los consumidores (mtk-smi-common,
# mtk-smi-larb, mtk_iommu, mediatek-drm...) hacen devm_clk_get(dev, "power")
# -> reloj 0x0d = SCP_SYS_DISP (PG_DISP).
#
# En el arbol 6.6 del A34, clk-mt6877-pg.c registra solo PG_MD, PG_MFG0-5 y
# PG_ADSP_DORMANT; PG_DISP y el resto estan comentados (el A34 mueve la
# gestion de mtcmos al driver genpd mtk-scpsys). Resultado en ruby:
#
#   mtk-smi-common 14002000.smi_common: CLK0:power get failed  (-ENOENT)
#   -> SMI no sondea -> mtk_ddp_comp_set_larb revienta (NULL deref) al
#   caducar el deferred probe del disp_ovl0.
#
# Aqui se descomentan TODOS los power-gates, igual que en el kernel stock de
# ruby (ruby-4.19), para que "power" (y el resto de relojes mtcmos) existan.
#
# Uso: ./port/clk/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  DM="$1/kernel/kernel_device_modules-6.6"
else
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

F="$DM/drivers/clk/mediatek/clk-mt6877-pg.c"
[ -f "$F" ] || { echo "falta $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import re, sys

p = sys.argv[1]
s = open(p).read()

# Idempotencia: si PG_DISP ya esta activo (sin //) no hay nada que hacer.
if re.search(r'^\tPGATE\(SCP_SYS_DISP,', s, re.M):
    print("  clk-mt6877-pg.c: power-gates ya descomentados")
    sys.exit(0)

new_block = '''struct mtk_power_gate scp_clks[] = {
	PGATE(SCP_SYS_MD, "PG_MD", NULL, NULL, NULL, SYS_MD),
	PGATE(SCP_SYS_CONN, "PG_CONN", NULL, NULL, NULL, SYS_CONN),
	PGATE(SCP_SYS_DISP, "PG_DISP", NULL, &mm_cg1, &mm_cg2, SYS_DISP),
	PGATE(SCP_SYS_MFG0, "PG_MFG0", NULL, NULL, NULL, SYS_MFG0),
	PGATE(SCP_SYS_MFG1, "PG_MFG1", "PG_MFG0", NULL, NULL, SYS_MFG1),
	PGATE(SCP_SYS_MFG2, "PG_MFG2", "PG_MFG0", NULL, NULL, SYS_MFG2),
	PGATE(SCP_SYS_MFG3, "PG_MFG3", "PG_MFG0", NULL, NULL, SYS_MFG3),
	PGATE(SCP_SYS_MFG4, "PG_MFG4", "PG_MFG0", NULL, NULL, SYS_MFG4),
	PGATE(SCP_SYS_MFG5, "PG_MFG5", "PG_MFG0", NULL, NULL, SYS_MFG5),
	PGATE(SCP_SYS_ISP0, "PG_ISP0", "PG_DISP", &isp0_cg1, &isp0_cg2, SYS_ISP0),
	PGATE(SCP_SYS_ISP1, "PG_ISP1", "PG_DISP", &isp1_cg1,
			&isp1_cg2, SYS_ISP1),
	PGATE(SCP_SYS_IPE, "PG_IPE", "PG_DISP", &ipe_cg1, &ipe_cg2, SYS_IPE),
	PGATE(SCP_SYS_VDEC, "PG_VDEC", "PG_DISP", &vde_cg1, &vde_cg2, SYS_VDEC),
	PGATE(SCP_SYS_VENC, "PG_VENC", "PG_DISP", &ven_cg1, &ven_cg2, SYS_VENC),
	PGATE(SCP_SYS_AUDIO, "PG_AUDIO", NULL, &audio_cg1,
			&audio_cg2, SYS_AUDIO),
	PGATE(SCP_SYS_ADSP_DORMANT, "PG_ADSP_DORMANT", NULL, &adsp_cg,
			NULL, SYS_ADSP_DORMANT),
	PGATE(SCP_SYS_CAM, "PG_CAM", "PG_DISP", &cam_cg1, &cam_cg2, SYS_CAM),
	PGATE(SCP_SYS_CAM_RAWA, "PG_CAM_RAWA", "PG_CAM", NULL,
			&cam_ra_cg, SYS_CAM_RAWA),
	PGATE(SCP_SYS_CAM_RAWB, "PG_CAM_RAWB", "PG_CAM", NULL,
			&cam_rb_cg, SYS_CAM_RAWB),
	PGATE(SCP_SYS_CSI, "PG_CSI", "PG_CAM", NULL,
			NULL, SYS_CSI),
	/* Gary Wang: no need to turn on disp mtcmos*/
	PGATE(SCP_SYS_APU, "PG_APU", NULL, &apu_cg, NULL, SYS_APU),
};'''

pat = re.compile(r'struct mtk_power_gate scp_clks\[\] = \{.*?\n\};', re.S)
m = pat.search(s)
if not m:
    sys.exit("clk-mt6877-pg.c: no encuentro el array scp_clks[]")

s = s[:m.start()] + new_block + s[m.end():]
open(p, 'w').write(s)
print("  clk-mt6877-pg.c: power-gates (PG_DISP y demas) descomentados")
PY
