#!/usr/bin/env bash
# Añade al GKI core las opciones de un fragmento (Android o Droidspaces).
# No toca device_modules. Idempotente.
#
# Uso: scripts/patch-gki-core.sh [fragmento]
set -euo pipefail
cd "$(dirname "$0")/.."

FRAG="${1:-configs/ruby-6.6/android.fragment}"
[ -f "$FRAG" ] || { echo "falta $FRAG" >&2; exit 1; }
K="sources/a34x/kernel-6.6/arch/arm64/configs/gki_defconfig"
[ -f "$K" ] || { echo "falta $K; ejecuta make fetch" >&2; exit 1; }

added=0
while IFS= read -r line; do
    case "$line" in
        ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    if grep -q "^${key}=" "$K"; then
        # actualiza el valor si difiere
        if ! grep -qxF "$line" "$K"; then
            sed -i "s|^${key}=.*|${line}|" "$K"
            echo "[gki] actualizado $key"
        fi
    else
        echo "$line" >> "$K"
        echo "[gki] añadido $line"
        added=$((added + 1))
    fi
done < "$FRAG"

echo "[gki] $added líneas nuevas desde $FRAG"
grep -nE 'CONFIG_(DEVTMPFS|TMPFS_XATTR|TMPFS_POSIX_ACL|SYSVIPC|PID_NS|IPC_NS|USER_NS|POSIX_MQUEUE|CGROUP_PIDS|CGROUP_DEVICE|CFS_BANDWIDTH|MACVLAN|NF_TABLES|NETFILTER_XT_MATCH_ADDRTYPE|CHECKPOINT_RESTORE)' "$K" || true
