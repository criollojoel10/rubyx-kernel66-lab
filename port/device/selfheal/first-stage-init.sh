#!/system/bin/sh
# /init de prueba: carga módulos y arma un watchdog que vuelve a A.
# Se usa SOLO en imágenes de test; no en el boot final.
exec >/dev/kmsg 2>&1
echo "RUBYFS first-stage start"
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null

SLOT="$(getprop ro.boot.slot_suffix 2>/dev/null)"
case "$SLOT" in
  "") SLOT="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^androidboot.slot_suffix=//p')" ;;
esac
echo "RUBYFS slot=$SLOT"

if [ "$SLOT" = "_b" ]; then
  (
    # Espera a que Android confirme el arranque; si no, vuelve al slot A.
    i=0
    while [ $i -lt 60 ]; do
      sleep 5
      i=$((i + 1))
      if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
        echo "RUBYFS watchdog: Android arrancado, no hace falta volver"
        exit 0
      fi
    done
    echo "RUBYFS watchdog: Android no confirmo, volviendo a A"
    /bctool set a --write
    sync
    reboot
  ) &
  echo "RUBYFS watchdog armed pid=$! (5 min)"
fi

MODDIR="/lib/modules/$(uname -r)"
[ -f "$MODDIR/modules.load" ] || MODDIR="/lib/modules"
for m in "$MODDIR/modules.load"; do
  [ -f "$m" ] || continue
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    path="$MODDIR/$name"
    [ -f "$path" ] || path="$MODDIR/${name}.ko"
    echo "RUBYFS insmod $path"
    insmod "$path"
    echo "RUBYFS insmod_rc=$? $path"
  done < "$m"
done

# El init stock no debe reintentar la carga (si no, aborta por modules.dep).
: > "$MODDIR/modules.load"

echo "RUBYFS exec /system/bin/init"
exec /system/bin/init
