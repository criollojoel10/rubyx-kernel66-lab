#!/usr/bin/env bash
# Lee el log de pstore del ruby por SSH. Solo lectura.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
OUT="logs/pstore-$(date -u +%Y%m%dT%H%M%SZ).txt"
ssh -o BatchMode=yes -o ConnectTimeout=10 termux \
  'su -c "cat /sys/fs/pstore/console-ramoops-0"' > "$OUT"
echo "$OUT ($(wc -c < "$OUT") bytes)"
