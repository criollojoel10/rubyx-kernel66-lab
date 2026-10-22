#!/usr/bin/env bash
# Verificacion del kernel ruby 6.6 en el dispositivo (solo lectura).
# Uso: scripts/verify-ruby.sh [host_ssh]
set -uo pipefail
cd "$(dirname "$0")/.."

HOST="${1:-termux}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST")

run() {
  echo
  echo "### $*"
  "${SSH[@]}" "su -c '$*'" 2>&1 | sed -e 's/\r$//'
}

echo "### kernel y slot"
"${SSH[@]}" 'uname -a; getprop ro.boot.slot_suffix; getprop sys.boot_completed' 2>&1

run "ls -l /dev/block/by-name/misc /dev/block/by-name/super /dev/block/by-name/userdata 2>&1"
run "cat /proc/partitions | grep -c 'sdc'"
run "dmesg | grep -iE 'ufshcd|scsi 0:0:0|Attached SCSI' | tail -8"
run "ls /sys/class/drm 2>/dev/null; cat /sys/class/drm/card0-DSI-1/status 2>/dev/null"
run "ls /sys/class/input 2>/dev/null | head -20"
run "ls /sys/class/power_supply 2>/dev/null"
run "getprop | grep -iE 'teei|soter|keymaster'"
run "ls -l /dev/teei_client /dev/ut_keymaster /dev/tz_vfs 2>&1"
run "dmesg | grep -iE 'gnss|gps' | tail -5"
run "/data/local/Droidspaces/bin/droidspaces check 2>&1 | tail -20"
run "getprop sys.boot_completed; adb devices 2>/dev/null | head -3"
