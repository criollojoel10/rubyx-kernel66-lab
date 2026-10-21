#!/usr/bin/env bash
# Aplica el parche kABI oficial de Droidspaces para GKI < 6.12.
# Variantes en orden recomendado por la doc oficial; si una no aplica, prueba
# la siguiente (usan distintos slots de padding).
set -euo pipefail
cd "$(dirname "$0")/.."

K="${1:-sources/a34x/kernel-6.6}"
[ -d "$K/include/linux" ] || { echo "falta $K (make fetch)" >&2; exit 1; }

PATCHES="
droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_3_4_5.patch
droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_1_2_3.patch
"

for p in $PATCHES; do
  [ -f "$p" ] || continue
  if patch -p1 -d "$K" --forward --dry-run < "$p" >/dev/null 2>&1; then
    patch -p1 -d "$K" --forward < "$p"
    echo "[kabi] aplicado: $p"
    exit 0
  fi
  echo "[kabi] no aplica (dry-run): $p"
done

echo "[kabi] ninguna variante aplicó; revisa el árbol $K" >&2
exit 1
