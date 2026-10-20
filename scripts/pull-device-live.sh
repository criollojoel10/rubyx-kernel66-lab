#!/usr/bin/env bash
# Recoge datos del ruby vivo por SSH/Termux. Solo lectura; no modifica nada.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-device/live}"
mkdir -p "$DEST"

capture() { # capture <archivo> <comando remoto>
  local name=$1 cmd=$2
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 termux "$cmd" > "$DEST/$name" 2> "$DEST/$name.err"; then
    printf '[live] AVISO: falló %s\n' "$name" >&2
  else
    printf '[live] %s\n' "$name" >&2
  fi
}

capture uname.txt 'uname -a'
capture cmdline.txt 'su -c "cat /proc/cmdline"'
capture meminfo.txt 'su -c "cat /proc/meminfo"'
capture iomem.txt 'su -c "cat /proc/iomem"'
capture interrupts.txt 'su -c "cat /proc/interrupts"'
capture dmesg.txt 'su -c "dmesg"'
capture getprop.txt 'getprop'
capture model.txt 'su -c "cat /proc/device-tree/model"'
capture compatible.bin 'su -c "cat /proc/device-tree/compatible"'
capture bootargs.txt 'su -c "cat /proc/device-tree/chosen/bootargs"'
capture memory-reg.hex 'su -c "od -An -tx1 /proc/device-tree/memory/reg"'
capture rtc0-name.txt 'su -c "cat /sys/class/rtc/rtc0/name"'
capture ufs.txt 'su -c "ls -l /sys/class/ufs"'
capture mmc.txt 'su -c "ls -l /sys/class/mmc_host"'
capture regulators.txt 'su -c "for r in /sys/class/regulator/*; do echo -n \"$r \"; cat $r/name; done"'
capture clk-summary.txt 'su -c "cat /sys/kernel/debug/clk/clk_summary"'
capture fdt-live.dtb 'su -c "cat /sys/firmware/fdt"'

tr '\0' '\n' < "$DEST/compatible.bin" > "$DEST/compatible.txt"
rm -f "$DEST/compatible.bin"

sha256sum "$DEST"/* > "$DEST/sha256sums.txt"
echo "[live] datos en $DEST" >&2
