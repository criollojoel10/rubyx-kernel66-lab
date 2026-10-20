#!/usr/bin/env bash
# Ejecuta el build oficial del A34 sin parches ni cambios.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="sources/a34x"
[ -d "$SRC" ] || { echo "falta $SRC; ejecuta make fetch" >&2; exit 1; }

mkdir -p logs
LOG="logs/a34-build-$(date -u +%Y%m%dT%H%M%SZ).log"
ENVLOG="logs/a34-build-env.txt"

{
  echo "fecha: $(date -u +%FT%TZ)"
  echo "host: $(uname -a)"
  echo "nproc: $(nproc)"
  echo "mem: $(free -h | sed -n 2p)"
  echo "disk:"; df -h .
  echo "commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "submodule: $(git -C "$SRC/kernel-6.6" rev-parse HEAD)"
  echo "version: $(sed -n '1,4p' "$SRC/kernel-6.6/Makefile" | tr '\n' ' ')"
} > "$ENVLOG"

echo "[build] log: $LOG" >&2

cd "$SRC"
set -o pipefail
bash build_kernel.sh 2>&1 | tee "../../$LOG"

echo "[build] terminó: $LOG" >&2
