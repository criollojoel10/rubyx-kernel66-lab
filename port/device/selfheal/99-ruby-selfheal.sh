#!/system/bin/sh
# Si arranca el slot B con un kernel de prueba, volver al Android A conocido.
# Se instala en /data/adb/service.d y se ejecuta con APatch root.
LOG=/data/adb/ruby/selfheal.log
mkdir -p /data/adb/ruby
exec >>"$LOG" 2>&1

echo "=== $(date -u +%FT%TZ) selfheal ==="
SLOT="$(getprop ro.boot.slot_suffix)"
KERNEL="$(uname -r)"
echo "slot=$SLOT kernel=$KERNEL boot_completed=$(getprop sys.boot_completed)"

[ "$SLOT" = "_b" ] || exit 0

if [ -e /data/adb/ruby/keep-b ]; then
  echo "keep-b presente: no se cambia de slot"
  exit 0
fi

# Dar tiempo a que Android termine de arrancar o a que falle.
i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i + 1))
done
echo "boot_completed=$(getprop sys.boot_completed) tras ${i}x2s"

PY=/data/data/com.termux/files/usr/bin/python3
if [ ! -x "$PY" ]; then
  echo "ERROR: no existe $PY; no puedo cambiar slot"
  exit 1
fi

"$PY" /data/adb/ruby/mtk-slot-local.py set a --write || {
  echo "ERROR: fallo al escribir slot A"
  exit 1
}
sync
echo "slot A escrito; reiniciando"
reboot
