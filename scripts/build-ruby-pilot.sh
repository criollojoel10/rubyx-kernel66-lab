#!/usr/bin/env bash
# Build del piloto pinctrl: A34 6.6.127 + pinctrl-mt6877 built-in.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="sources/a34x"
[ -d "$SRC/kernel-6.6" ] || { echo "falta $SRC; ejecuta make fetch" >&2; exit 1; }
mkdir -p logs
LOG="logs/ruby-pilot-$(date -u +%Y%m%dT%H%M%SZ).log"

# 1. Aplicar el driver al GKI.
./port/pinctrl/apply.sh "$SRC/kernel-6.6"

# 2. Copiar el overlay al árbol de configs del build.
cp configs/ruby-6.6-minimal/ruby_pilot.config \
   "$SRC/kernel/kernel_device_modules-6.6/kernel/configs/ruby_pilot.config"

# 3. Copiar el script oficial y añadir solo el overlay del piloto.
cp "$SRC/build_kernel.sh" "$SRC/build_kernel_pilot.sh"
python3 - "$SRC/build_kernel_pilot.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'mt6877_teegris_5_overlay.config"'
new = 'mt6877_teegris_5_overlay.config ruby_pilot.config"'
if old not in s:
    raise SystemExit("no se encontró la lista de overlays en build_kernel.sh")
open(p, "w").write(s.replace(old, new, 1))
PY

# 4. Build.
cd "$SRC"
set -o pipefail
bash build_kernel_pilot.sh 2>&1 | tee "../../$LOG"
echo "[pilot] log: $LOG" >&2
