#!/usr/bin/env bash
# Prueba controlada: boot_b + slot B + retorno automático a Android A.
# Uso: ./scripts/run-slot-b-test.sh [/tmp/ruby-diag-stockdtb.img]
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-/tmp/ruby-diag-stockdtb.img}"
mkdir -p logs
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="logs/slotb-$TS.log"
exec > >(tee -a "$LOG") 2>&1

say() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 termux)

say "inicio $TS"
[ -f "$IMG" ] || { echo "falta $IMG"; exit 1; }
LOCAL_SHA="$(sha256sum "$IMG" | awk '{print $1}')"
say "imagen local: $IMG sha256=$LOCAL_SHA size=$(stat -c%s "$IMG")"

say "estado de slot actual"
./scripts/mtk-slot.py status

say "espacio en /sdcard"
"${SSH[@]}" 'df -h /sdcard | tail -1'

say "copiando imagen a Termux"
scp -q "$IMG" termux:/sdcard/ruby-diag.img
DEV_SHA="$("${SSH[@]}" "sha256sum /sdcard/ruby-diag.img" | awk '{print $1}')"
[ "$DEV_SHA" = "$LOCAL_SHA" ] || { echo "hash remoto no coincide: $DEV_SHA"; exit 1; }
say "hash remoto OK"

say "escribiendo boot_b"
"${SSH[@]}" 'su -c "dd if=/sdcard/ruby-diag.img of=/dev/block/by-name/boot_b bs=4M conv=fsync"'
RB="$("${SSH[@]}" 'su -c "dd if=/dev/block/by-name/boot_b bs=4M count=32 2>/dev/null | sha256sum"' | awk '{print $1}')"
[ "$RB" = "$LOCAL_SHA" ] || { echo "readback boot_b no coincide: $RB"; exit 1; }
say "readback boot_b OK"

say "marcando slot B (tries=1)"
./scripts/mtk-slot.py set b --write
say "slot B escrito; reiniciando"
REBOOT_AT="$(date -u +%s)"
if ! "${SSH[@]}" 'su -c reboot' 2>/dev/null; then
  say "ssh se cerró al reiniciar (esperado)"
fi

say "esperando retorno a Android A"
OK=0
for i in $(seq 1 72); do
  sleep 5
  if OUT="$("${SSH[@]}" 'getprop sys.boot_completed; getprop ro.boot.slot_suffix' 2>/dev/null)"; then
    BOOTED="$(printf '%s\n' "$OUT" | sed -n 1p)"
    SLOT="$(printf '%s\n' "$OUT" | sed -n 2p)"
    say "ssh responde (intento $i): boot_completed=$BOOTED slot=$SLOT"
    if [ "$BOOTED" = "1" ]; then
      OK=1
      break
    fi
  fi
done
END_AT="$(date -u +%s)"
say "tiempo total desde reboot: $((END_AT-REBOOT_AT)) s"

if [ "$OK" != "1" ]; then
  say "FALLO: no volvió Android en el plazo. Recuperación por PC."
  exit 1
fi

say "Android A de vuelta"
./scripts/mtk-slot.py status
./scripts/read-pstore.sh
say "log: $LOG"
