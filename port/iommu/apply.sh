#!/usr/bin/env bash
# Blindaje del registro de fault-callback del IOMMU (mediatek_v2).
#
# mtk_iommu_register_fault_callback() -> mtk_iommu_port_idx() dereferencia
# m4u_data (puntero global que solo setea el probe de mtk_iommu.ko) sin
# comprobar NULL. Si el IOMMU no llego a sondear (p.ej. porque el SMI todavia
# falla), el init de un componente del display llama a este callback y revienta:
#
#   [DISP]mtk_ddp_comp_set_larb: OVL0 need larb device, smi-id:0
#   Unable to handle kernel NULL pointer dereference at virtual address 0x18
#   (0x18 = offset del campo plat_data en struct mtk_m4u16_data)
#
# Se anade un guard en mtk_iommu_port_idx() para que devuelva -1 (igual que el
# camino "port no encontrado") en vez de desreferenciar NULL. Protege tanto a
# mtk_iommu_register_fault_callback como a mtk_iommu_unregister_fault_callback.
#
# Uso: ./port/iommu/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  DM="$1/kernel/kernel_device_modules-6.6"
else
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

F="$DM/drivers/misc/mediatek/iommu/iommu_debug.c"
[ -f "$F" ] || { echo "falta $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import sys

p = sys.argv[1]
s = open(p).read()

MARKER = "m4u_data not ready (iommu not probed)"
if MARKER in s:
    print("  iommu_debug.c: guard de m4u_data ya presente")
    sys.exit(0)

anchor = '''	if (type < MM_IOMMU || type >= TYPE_NUM || idx_list == NULL) {
		pr_info("%s, invalid parameter, type=%d\\n", __func__, type);
		return -1;
	}
'''
assert anchor in s, "no encuentro el bloque de validacion de mtk_iommu_port_idx"

guard = '''	if (!m4u_data || !m4u_data->plat_data) {
		pr_info("%s, m4u_data not ready (iommu not probed)\\n", __func__);
		return -1;
	}
'''
s = s.replace(anchor, anchor + "\n" + guard, 1)
open(p, 'w').write(s)
print("  iommu_debug.c: guard de m4u_data anadido en mtk_iommu_port_idx")
PY
