# 39 — Primer arranque Android con módulos

## Objetivo

Arrancar el `init` stock de ruby con el kernel 6.6 del A34 y los módulos de
storage, sin cambiar el init de diagnóstico todavía.

## Ramdisk

El ramdisk stock se extrae del boot_b original:

```sh
unpack_bootimg --boot_img device/backups/boot_b-stock.img --out /tmp/stockboot
lz4 -d /tmp/stockboot/ramdisk /tmp/stockboot/ramdisk.cpio
mkdir -p /tmp/stockboot/rd
(cd /tmp/stockboot/rd && cpio -idm < ../ramdisk.cpio)
```

Contiene `first_stage_ramdisk/system/etc/fstab.mt6877` con las entradas de
`super`, `userdata`, `metadata` y `misc`, y `/lib/modules/modules.load` es la
ruta que lee el init de Android.

## Inyección

```sh
scripts/pack-stock-modules-ramdisk.sh \
  /tmp/stockboot/rd /tmp/ufs-order /tmp/stock-modules.ramdisk.lz4
```

El `Image` del A34 (37 MB) no cabe junto al ramdisk stock (20 MB) antes del
footer AVB de 40 MB. La solución validada es usar `Image.gz` (15 MB):

```sh
scripts/build-diag-boot.py \
  --original device/backups/boot_b-stock.img \
  --kernel artifacts/a34-6.6.127/Image.gz \
  --initramfs /tmp/stock-modules.ramdisk.lz4 \
  --dtb /tmp/ruby-regfix.dtb \
  --out /tmp/stock-modules-gz.img
```

LK acepta el kernel comprimido: la prueba de diagnóstico con `Image.gz`
arrancó Linux 6.6.127 y enumeró `sdc1..77`.

## Criterio

- `/lib/modules/modules.load` existe y carga UFS/PHY/IOMMU/reset.
- `init` llega a `first_stage_mount`.
- `/dev/block/by-name/{super,userdata,metadata,misc}` existen.
- Si Android no arranca, el slot B vuelve a A por `tries=1`.

## APatch

Antes de probar Droidspaces, el dispositivo debe tener APatch con superkey
vacía. Ver `docs/38-droidspaces-apatch.md` y ejecutar:

```sh
scripts/check-device-root.sh
```
