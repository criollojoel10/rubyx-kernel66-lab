#!/usr/bin/env bash
# Build A34 6.6.127 con dos optimizaciones de caché:
#  - SOURCE_DATE_EPOCH fijo (claves Bazel estables)
#  - Clang r536225 cacheado en ~/.cache/ruby
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="sources/a34x"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta make fetch" >&2; exit 1; }
mkdir -p logs
mkdir -p "$HOME/.cache/bazel-disk" "$HOME/.cache/bazel-repo"
export DEBUG_ARGS="--disk_cache=$HOME/.cache/bazel-disk --repository_cache=$HOME/.cache/bazel-repo"
export KBUILD_BUILD_TIMESTAMP="2025-01-01 00:00:00 UTC"
LOG="logs/a34-fast-$(date -u +%Y%m%dT%H%M%SZ).log"

cp "$SRC/build_kernel.sh" "$SRC/build_kernel_fast.sh"
python3 - "$SRC/build_kernel_fast.sh" <<'PY'
import re
import sys
p = sys.argv[1]
s = open(p).read()

# 1. Reutilizar clang cacheado y guardarlo tras la primera descarga.
old = '''wget -O clang-r536225.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel-2025/clang-r536225.tar.gz
mkdir clang-r536225; cd clang-r536225
tar xvzf ../clang-r536225.tar.gz
rm ../clang-r536225.tar.gz
cd ..'''
new = '''if [ -d "$HOME/.cache/ruby/clang-r536225" ]; then
  cp -a "$HOME/.cache/ruby/clang-r536225" ./clang-r536225
else
  wget -O clang-r536225.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel-2025/clang-r536225.tar.gz
  mkdir -p clang-r536225
  tar xvzf clang-r536225.tar.gz -C clang-r536225
  rm clang-r536225.tar.gz
  mkdir -p "$HOME/.cache/ruby"
  cp -a clang-r536225 "$HOME/.cache/ruby/clang-r536225"
fi'''
if old not in s:
    raise SystemExit("no se encontró el bloque de descarga de clang")
s = s.replace(old, new, 1)

# 2. Fijar el stamping para que las acciones de Bazel sean reutilizables.
s = s.replace(r'$(date +%s)', '1700000000')
s = s.replace(r'$\(date \+\%s\)', '1700000000')

# 3. Permitir reutilizar un aosp-kernel existente.
s = s.replace('mkdir aosp-kernel && cd aosp-kernel',
              'mkdir -p aosp-kernel && cd aosp-kernel', 1)

open(p, "w").write(s)
PY

# 4. Overlay opcional (p. ej. UFS upstream para ruby).
if [ -n "${RUBY_OVERLAY:-}" ]; then
  cp "$RUBY_OVERLAY" "$SRC/kernel/kernel_device_modules-6.6/kernel/configs/ruby_overlay.config"
  python3 - "$SRC/build_kernel_fast.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'mt6877_teegris_5_overlay.config"'
new = 'mt6877_teegris_5_overlay.config ruby_overlay.config"'
if old not in s:
    raise SystemExit("no se encontró la lista de overlays")
open(p, "w").write(s.replace(old, new, 1))
PY
fi

cd "$SRC"
set -o pipefail
bash build_kernel_fast.sh 2>&1 | tee "../../$LOG"
echo "[fast] log: $LOG" >&2
