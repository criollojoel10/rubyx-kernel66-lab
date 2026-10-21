# 31 — Auditoría UFS A34 sin Samsung

## Makefile real

`drivers/ufs/vendor/Makefile`:

```
obj-$(CONFIG_DEVICE_MODULES_SCSI_UFS_MEDIATEK) += ufs-mediatek-mod.o
ufs-mediatek-mod-y += ../ufs-mediatek.o ../ufs-mediatek-sysfs.o \
                      ../ufs-mediatek-mimic.o ../ufs-mediatek-mbrain.o
ufs-mediatek-mod-$(CONFIG_SEC_UFS_FEATURE) += ufs-sec-feature.o ufs-sec-sysfs.o
ufs-mediatek-mod-$(CONFIG_MTK_BLOCK_IO_TRACER) += ../ufs-mediatek-btag.o
ufs-mediatek-mod-$(CONFIG_RPMB) += ../ufs-mediatek-rpmb.o
```

También se compila `ufs-mediatek-mod-ise.o` con las mismas fuentes y
`ufs-mediatek-ise.o` si `CONFIG_RPMB`.

## Qué mete a Samsung

- `SEC_UFS_FEATURE` → `ufs-sec-feature.o`, `ufs-sec-sysfs.o`
  (`sec_debug_get_force_upload`, `linux/sec_debug.h`).
- `SCSI_UFS_MEDIATEK_DBG` → `ufs-mediatek-dbg.o` con
  `<mt-plat/mrdump.h>` y `mrdump_*`.
- `MTK_BLOCK_IO_TRACER` → `ufs-mediatek-btag.o`.
- `SEC_DEBUG`/`SEC_ABC` activan la cadena que termina en `sec_ext`.

## Por qué desactivarlo es seguro

En `ufs-mediatek.c` todas las llamadas Samsung están protegidas:

```c
#if IS_ENABLED(CONFIG_SEC_UFS_FEATURE)
    ufs_sec_check_device_stuck();
#endif
```

Lo mismo en `ufs_mtk_host_reset`, `ufs_mtk_adjust_caps_quirks`,
`ufs_mtk_init`, etc. Sin `SEC_UFS_FEATURE`, el glue MTK compila sin
`ufs-sec-feature.o`.

## Fragmento mínimo

```
CONFIG_DEVICE_MODULES_SCSI_UFS_MEDIATEK=m
CONFIG_DEVICE_MODULES_PHY_MTK_UFS=m
CONFIG_DEVICE_MODULES_MTK_IOMMU=m
# CONFIG_SEC_UFS_FEATURE is not set
# CONFIG_SCSI_UFS_MEDIATEK_DBG is not set
# CONFIG_MTK_BLOCK_IO_TRACER is not set
# CONFIG_SEC_DEBUG is not set
# CONFIG_SEC_ABC is not set
```

`ufs-mediatek-mod.ko` debe quedar dependiendo solo de MTK/GKI, no de
`sec_ext`, `abc`, `mrdump` ni `blocktag`.

## Módulo a cargar

Usar `ufs-mediatek-mod.ko` (sin iSE). El `-ise` solo hace falta para RPMB/iSE.

## Build

Run `39591728145`:

```
A34 + device_modules UFS sin Samsung
```

Cuando termine:

```
modinfo -F depends ufs-mediatek-mod.ko
```

No debe listar `sec_ext`/`sec_debug`. Después se calcula el cierre con
`phy-mtk-ufs`, `mtk_iommu` y los 11 módulos base.
