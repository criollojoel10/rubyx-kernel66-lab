#!/usr/bin/env bash
# Verificacion del kernel ruby 6.6 en el dispositivo (solo lectura).
#
# Comprueba el contrato kernel <-> user space del vendor (ver
# docs/98-android-lado.md): entradas de /proc, nodos de /dev, sysfs termico,
# typec, carga, display, camara, TEE y los requisitos de Droidspaces.
#
# Uso: scripts/verify-ruby.sh [host_ssh]
set -uo pipefail
cd "$(dirname "$0")/.."

HOST="${1:-termux}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST")

REMOTE='
f() { # f <etiqueta> <comando>
  out=$(eval "$2" 2>/dev/null | tr "\n" " ")
  if [ -n "$out" ]; then echo "OK    $1 | $out"; else echo "FALTA $1"; fi
}

echo "### kernel"
f "version"      "uname -r"
f "slot"         "getprop ro.boot.slot_suffix"
f "boot_completed" "getprop sys.boot_completed"
f "modulos cargados" "wc -l < /proc/modules"

echo "### contrato /proc"
for p in displowpower mi_display mtk_battery_cmd mtk_lpm mtk_mali mtk_mdp_debug \
         mtk_pm_qos mtk_rtc mtk_typec mtkcooler mtkfb mtkfb_debug; do
  f "proc/$p" "test -e /proc/$p && echo presente"
done

echo "### contrato /dev"
for d in camera-dip camera-dpe camera-fdvt camera-isp camera-mfb camera-rsc \
         camera-wpe kd_camera_hw ccci_ioctl0 ccci_c2k_agps gpsdl0 gpsdl1 \
         gps_emi isee_tee0 mi_display mtk_mdp; do
  f "dev/$d" "test -e /dev/$d && echo presente"
done

echo "### termica y typec"
f "cooling devices" "ls /sys/class/thermal/cooling_device* 2>/dev/null | wc -l"
f "typec port"     "ls /sys/class/typec/port0 2>/dev/null | tr \"\\n\" \" \""

echo "### carga"
f "power_supply"   "ls /sys/class/power_supply 2>/dev/null | tr \"\\n\" \" \""
f "charge limits"  "cat /sys/class/power_supply/primary_chg/charge_control_limits_max_current 2>/dev/null"
f "battery"        "dumpsys battery 2>/dev/null | grep -E \"status:|level:|voltage:|Max charging current\" | tr \"\\n\" \" \""

echo "### display y camara"
f "drm"            "cat /sys/class/drm/card0-DSI-1/status 2>/dev/null; cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1"
f "camaras"        "dumpsys media.camera 2>/dev/null | grep -E \"Number of camera devices\" | tr \"\\n\" \" \""

echo "### tactil (Focaltech FT3680 por SPI3)"
f "input devices"  "cat /proc/bus/input/devices 2>/dev/null | grep -E "^N: Name" | tr "\\n" " \";""
f "eventos touch"  "ls /dev/input/ 2>/dev/null | tr "\\n" " \";""
f "driver del panel" "grep -m1 -E "fts_ts|focaltech|goodix|mtk_tpd" /proc/bus/input/drivers 2>/dev/null"
f "multitouch"     "getevent -pl 2>/dev/null | grep -c ABS_MT_SLOT"

echo "### TEE y GPS"
f "tee nodes"      "ls /dev/teei_client /dev/teei_config /dev/ut_keymaster /dev/isee_tee0 2>/dev/null | tr \"\\n\" \" \""
f "gps"            "ls /dev/gpsdl0 /dev/gps_emi /dev/socket/mnld 2>/dev/null | tr \"\\n\" \" \""

echo "### salud del kernel"
f "avc denied"     "dmesg | grep -c \"avc: denied\""
f "errores de modulos" "dmesg | grep -ciE \"invalid module format|disagrees about version of symbol\""
f "conn bus timeouts" "dmesg | grep -c ahb_apb_timeout"
f "pstore"         "ls /sys/fs/pstore 2>/dev/null | head -3 | tr \"\\n\" \" \""

echo "### droidspaces"
f "droidspaces check" "/data/local/Droidspaces/bin/droidspaces check 2>&1 | tail -25"
'

echo "=== verificacion del kernel ruby 6.6 en $HOST ==="
"${SSH[@]}" "su -c '$REMOTE'" 2>&1 | sed -e 's/\r$//'
