#!/usr/bin/env bash
# Añade al GKI core las opciones que no están en gki_defconfig.
# No toca device_modules. Idempotente.
set -euo pipefail
cd "$(dirname "$0")/.."
K="sources/a34x/kernel-6.6/arch/arm64/configs/gki_defconfig"
[ -f "$K" ] || { echo "falta $K; ejecuta make fetch" >&2; exit 1; }

append() {
    local opt="$1"
    grep -qxF "$opt" "$K" || echo "$opt" >> "$K"
}

append 'CONFIG_DEVTMPFS=y'
append 'CONFIG_DEVTMPFS_MOUNT=y'
append 'CONFIG_TMPFS_XATTR=y'
append 'CONFIG_TMPFS_POSIX_ACL=y'

echo "[gki] opciones Android aplicadas en $K"
grep -nE 'CONFIG_(DEVTMPFS|TMPFS_XATTR|TMPFS_POSIX_ACL)' "$K"
