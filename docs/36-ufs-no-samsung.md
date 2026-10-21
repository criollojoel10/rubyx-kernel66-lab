# 36 — UFS propio compilado sin Samsung

## Build

```
Run 39627025334   success
Duración ~47 min
```

Artefacto `a34-storage`:

```
Image.gz
a34-all-modules.tar.zst
device-modules.config
```

Config final:

```
CONFIG_DEVICE_MODULES_SCSI_UFS_MEDIATEK=m
CONFIG_DEVICE_MODULES_PHY_MTK_UFS=m
CONFIG_DEVICE_MODULES_MTK_IOMMU=m
```

## Dependencias reales del UFS

```
ufs-mediatek-mod: irq-dbg,rpmb
```

No depende de `sec_ext`, `sec_debug`, `abc`, `mrdump` ni `blocktag`.

`SEC_DEBUG`/`SEC_ABC` siguen como módulos del A34, pero el UFS ya no los
enlaza. En el initramfs de storage:

```
25 módulos
sec_ext: 0
```

`mrdump` depende de `sec_debug`; `sec_debug` no tiene dependencias y no
arrastra `sec_ext`.

## Imagen de storage

```
Run 39634896615   success
ruby-storage-boot.img
sha256 7f3225e4604c850688da2aba44bf7bfc977a7dcdf287d6dad89931f289f773f3
```

```
header v2
kernel  15 676 932 B
ramdisk  5 172 064 B
dtb        179 207 B
cmdline stock
```

Initramfs: 25 módulos, incluidos UFS, PHY, IOMMU, SMI, rpmb, irq-dbg y los
11 base.

DTB:

```
445 symbols
62/62 dtbo targets
```

## Pendiente

Probar en `boot_b`:

1. escribir la imagen;
2. marcar B con `tries=1`;
3. reiniciar;
4. leer pstore y comprobar `sdc1`/`misc`.

No se ha flasheado todavía.
