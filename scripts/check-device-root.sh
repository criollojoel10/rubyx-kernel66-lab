#!/usr/bin/env bash
# Comprueba root por APatch sin introducir superkey (debe estar vacía).
set -euo pipefail

HOST="${HOST:-termux}"
export APATCH_SUPERKEY="${APATCH_SUPERKEY:-}"

echo "[root] host=$HOST APATCH_SUPERKEY=${APATCH_SUPERKEY:+<set>}${APATCH_SUPERKEY:-<empty>}"
id_out="$(ssh -o BatchMode=yes "$HOST" 'su -c id' 2>&1)" || {
  echo "[root] FAIL: su -c id falló; revisa APatch/superkey" >&2
  printf '%s\n' "$id_out" >&2
  exit 1
}
printf '%s\n' "$id_out"
case "$id_out" in
  *"uid=0(root)"*) ;;
  *) echo "[root] FAIL: no es uid=0" >&2; exit 1 ;;
esac

echo "[root] OK: APatch concede root sin prompt"
