#!/usr/bin/env bash
# Prepara los ficheros de init que necesita el GPS (y el resto) para una
# imagen de ruby con el kernel 6.6 del laboratorio.
#
# En el kernel stock de ruby el GPS va built-in, asi que no hay nada que
# cargar. En el nuestro el stack GNSS de MTK 6.6 son modulos (.ko) que
# carga el init de MTK con:
#
#   on property:vendor.connsys.driver.ready=yes
#     insmod /vendor/lib/modules/${ro.vendor.gps.chrdev}.ko
#
# pero el vendor de ruby NO define ro.vendor.gps.chrdev (en el stock no
# hacia falta), asi que hay que ponerla. El nombre del modulo es
# gps_drv_stp (MODULE_NAME en el Kbuild de gps_stp).
#
# Uso: ./scripts/pack-init-rc.sh <directorio-del-ramdisk>
set -euo pipefail

RAMDISK="${1:?falta el directorio del ramdisk}"
[ -d "$RAMDISK" ] || { echo "no existe $RAMDISK" >&2; exit 1; }

mkdir -p "$RAMDISK/etc/rubyx" "$RAMDISK/etc/init.d"

# 1) propiedad que usa el .rc de MTK para saber que modulo cargar
cat > "$RAMDISK/etc/rubyx/gps.prop" <<'EOF'
ro.vendor.gps.chrdev=gps_drv_stp
EOF

# 2) el .rc de MTK, adaptado: sin la propiedad (no existe en el vendor) se
#    carga el modulo directamente cuando connsys esta listo
cat > "$RAMDISK/etc/init.d/rubyx-gps.rc" <<'EOF'
# GPS de MTK 6.6 para ruby (modulos del stack GNSS de connectivity).
# El vendor de ruby no define ro.vendor.gps.chrdev porque en el kernel
# stock el GPS va built-in; aqui se carga el modulo.

on property:vendor.connsys.driver.ready=yes
    insmod /lib/modules/gps_drv_stp.ko
EOF

# 3) los .rc de MTK que vienen con los modulos (data_link, gps_pwr, gps_scp)
#    con el path corregido (/lib/modules en vez de /vendor/lib/modules)
VENDOR="$(cd "$(dirname "$0")/.." && pwd)/sources/a34x/vendor/mediatek/kernel_modules/connectivity/gps"
if [ -d "$VENDOR" ]; then
  for rc in data_link/init.gps_drv.rc gps_pwr/init.gps_pwr.rc gps_scp/init.gps_scp.rc; do
    [ -f "$VENDOR/$rc" ] || continue
    out="$RAMDISK/etc/init.d/rubyx-$(basename "$rc")"
    sed -e 's|/vendor/lib/modules/|/lib/modules/|g' \
        -e "s|\${ro.vendor.gps.chrdev}|gps_drv_stp|g" \
        "$VENDOR/$rc" > "$out"
    echo "  (rc: $(basename "$rc"))"
  done
fi

echo "[init-rc] ficheros de init para el GPS en $RAMDISK/etc"
