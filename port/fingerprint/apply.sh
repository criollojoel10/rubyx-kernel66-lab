#!/usr/bin/env bash
# Aplica el driver de la huella Goodix de ruby al GKI 6.6.
#
# Los device modules no se compilan (ALLOW_BUILTIN=n), asi que va al GKI.
# Uso: ./port/fingerprint/apply.sh [raiz/del/gki]
set -euo pipefail
cd "$(dirname "$0")/../.."

GKI="${1:-sources/a34x/kernel-6.6}"
IN="$GKI/drivers/input"
[ -d "$IN" ] || { echo "no existe $IN" >&2; exit 1; }

SRC="port/fingerprint/goodix_cap"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta scripts/port-fingerprint-goodix.py" >&2; exit 1; }

rm -rf "$IN/fingerprint"
mkdir -p "$IN/fingerprint"
cp -a "$SRC" "$IN/fingerprint/goodix_cap"

# Makefile y Kconfig del directorio nuevo
cat > "$IN/fingerprint/Makefile" <<'EOF'
# Huella de ruby
obj-$(CONFIG_GOODIX_CAP_FINGERPRINT) += goodix_cap/
EOF

cat > "$IN/fingerprint/Kconfig" <<'EOF'
source "drivers/input/fingerprint/goodix_cap/Kconfig"
EOF

# enganche en drivers/input
grep -q '^obj-y += fingerprint/' "$IN/Makefile" || echo 'obj-y += fingerprint/' >> "$IN/Makefile"
grep -q 'drivers/input/fingerprint/Kconfig' "$IN/Kconfig" || \
  echo 'source "drivers/input/fingerprint/Kconfig"' >> "$IN/Kconfig"

echo "[fingerprint] driver Goodix aplicado en $IN/fingerprint/goodix_cap"
