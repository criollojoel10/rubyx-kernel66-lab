#!/usr/bin/env bash
# Inventario EN VIVO de los subsistemas de ruby en el telefono (root, APatch).
# Solo lectura: no toca nada del dispositivo.
#
# Uso: scripts/inventario-vivo.sh [host_ssh] > docs/evidence/inventario-<fecha>.txt
set -uo pipefail
cd "$(dirname "$0")/.."

HOST="${1:-termux}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST")

REMOTE='
echo "### kernel y slot"
uname -a
getprop ro.boot.slot_suffix
getprop sys.boot_completed
getprop ro.build.version.release

echo
echo "### modulos cargados (los de plataforma)"
awk "{print \$1}" /proc/modules | grep -viE "^(nf_|netfilter|nls|af_alg|dummy|loop|xt_|ebtable|ip6_|crc|ppp|rfcomm|bnep|hidp|sdio|cmac|llc|8021q|sch_|tun|wireguard)" | head -60

echo
echo "### 1. TEE / keymaster / FBE"
ls -l /dev/teei_client /dev/teei_config /dev/teei_fp /dev/ut_keymaster /dev/isee_tee0 /dev/tz_vfs 2>&1 | head -10
dmesg | grep -iE "teei|keymaster|tee_|tz_driver" | tail -8
getprop | grep -iE "keymaster|teei|soter" | head -5
dumpsys android.security.keystore 2>/dev/null | head -5

echo
echo "### 2. huella (goodix fp por SPI)"
dmesg | grep -iE "goodix|gf_|fingerprint|fpc" | tail -8
ls -l /dev/*fp* /dev/*goodix* 2>&1 | head -5
dumpsys fingerprint 2>/dev/null | head -12

echo
echo "### 3. audio (altavoz aw882xx, haptic aw869x)"
ls /sys/class/sound/ 2>/dev/null
cat /proc/asound/cards 2>/dev/null
dmesg | grep -iE "aw882|aw869|smartpa|awinic|snd_soc" | tail -10
ls /sys/class/leds/ 2>/dev/null | head -20

echo
echo "### 4. camara"
dumpsys media.camera 2>/dev/null | grep -iE "Number of camera|Camera [0-9]|facing" | head -12
dmesg | grep -iE "imgsensor|camera|mipi" | tail -8
ls /dev/video* /dev/camera* 2>&1 | head -8

echo
echo "### 5. sensores"
for s in accel gyro alsps_mtk psensor mag hall proximity; do
  printf "%-12s " "$s"; ls -d /sys/class/$s 2>/dev/null || echo "-"
done
ls /sys/class/sensors_class/ 2>/dev/null | head -20
dumpsys sensorservice 2>/dev/null | head -12

echo
echo "### 6. GPS"
ls -l /dev/gps* /dev/emi* /dev/socket/mnld 2>&1 | head -8
dmesg | grep -iE "gnss|gps|stp|mnld" | tail -8
dumpsys location 2>/dev/null | grep -iE "gps provider|Location: " | head -6
getprop | grep -iE "gps|gnss" | head -5

echo
echo "### 7. wifi / bluetooth"
ip -br link 2>/dev/null | head -6
getprop | grep -iE "wifi|bluetooth" | head -8
dumpsys wifi 2>/dev/null | grep -iE "Wi-Fi is|mCurrentState" | head -4
dumpsys bluetooth_manager 2>/dev/null | grep -iE "enabled|state" | head -4

echo
echo "### 8. carga y alimentacion"
ls /sys/class/power_supply/ 2>/dev/null
dumpsys battery 2>/dev/null | head -12
for p in /sys/class/power_supply/*/; do
  n=$(basename "$p")
  printf "%-16s type=%s status=%s online=%s\n" "$n" \
    "$(cat $p/type 2>/dev/null)" "$(cat $p/status 2>/dev/null)" "$(cat $p/online 2>/dev/null)"
done
dmesg | grep -iE "charger|mp2762|ln8000|xmusb|bq25980|sc8561|max77932|bq28z" | tail -10

echo
echo "### 9. display"
ls /sys/class/drm/ 2>/dev/null
cat /sys/class/drm/card0-DSI-1/status 2>/dev/null
cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -3
dmesg | grep -iE "panel|dsi|drm|disp" | tail -8

echo
echo "### 10. tactil"
cat /proc/bus/input/devices 2>/dev/null | grep -E "^N: Name|^H: Handlers" | head -20
dmesg | grep -iE "fts_|focal|goodix|touchscreen" | tail -6

echo
echo "### 11. droidspaces"
ls -l /data/local/Droidspaces/bin/ 2>&1 | head -5
/data/local/Droidspaces/bin/droidspaces check 2>&1 | tail -30
'

echo "=== inventario en vivo de ruby ($HOST) ==="
"${SSH[@]}" "su -c '$REMOTE'" 2>&1 | sed -e 's/\r$//'
