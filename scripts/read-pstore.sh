#!/usr/bin/env bash
# Lee el log de pstore del ruby por SSH. Solo lectura.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="logs/pstore-$STAMP.txt"
ssh -o BatchMode=yes -o ConnectTimeout=10 termux \
  'su -c "cat /sys/fs/pstore/console-ramoops-0"' > "$OUT"
echo "$OUT ($(wc -c < "$OUT") bytes)"
if ssh -o BatchMode=yes -o ConnectTimeout=10 termux \
    'su -c "test -f /sys/fs/pstore/pmsg-ramoops-0"'; then
  PMSG="logs/pmsg-$STAMP.txt"
  ssh -o BatchMode=yes -o ConnectTimeout=10 termux \
    'su -c "cat /sys/fs/pstore/pmsg-ramoops-0"' > "$PMSG"
  echo "$PMSG ($(wc -c < "$PMSG") bytes)"
fi
