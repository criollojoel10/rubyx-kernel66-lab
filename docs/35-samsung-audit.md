# 35 — Auditoría de dependencias Samsung restantes

## Referencias a `ufs_sec_*`

Solo aparecen en:

```
drivers/ufs/ufs-mediatek.c        (todas bajo #if IS_ENABLED(CONFIG_SEC_UFS_FEATURE))
drivers/ufs/vendor/ufs-sec-feature.c
drivers/ufs/vendor/ufs-sec-sysfs.c
block/blk-sec-common.c
block/blk-sec-wb.c
```

Con `SEC_UFS_FEATURE=n` no se compilan los dos `ufs-sec-*`; con
`BLK_SEC_COMMON/WB` fuera no se compilan los `blk-sec-*`.

## Referencias a `blk_sec_*`

Solo en:

```
block/blk-sec-common.c
block/blk-sec-wb.c
block/blk-sec-stat*.c
block/ssg-iosched.c
block/ssg-wb.c
```

Los `blk-sec-*` están fuera del `Makefile`; `ssg-*` se desactiva con
`MQ_IOSCHED_SSG*`.

## Símbolos desactivados

Defconfigs A34:

```
SEC_UFS_FEATURE
SCSI_UFS_MEDIATEK_DBG
MTK_BLOCK_IO_TRACER
BLK_SEC_COMMON
BLK_SEC_STATS
BLK_SEC_WB
MQ_IOSCHED_SSG
MQ_IOSCHED_SSG_CGROUP
MQ_IOSCHED_SSG_WB
```

También se comentan en `block/Makefile`:

```
#obj-$(CONFIG_BLK_SEC_COMMON)
#obj-$(CONFIG_BLK_SEC_WB)
#obj-$(CONFIG_MQ_IOSCHED_SSG)
```

Y el stub de `blk-sec.h` queda `__attribute__((unused))`.

## Lo que queda

`SEC_DEBUG` y `SEC_ABC` siguen como módulos (`m`) del A34, pero **ya no son
dependencia del UFS**: `ufs-mediatek-mod` no incluye `ufs-sec-feature.o`.
No se cargan en el initramfs de storage.

`UFSFEATURE`, `UFSSHPB`, `UFSTW`, `UFSHID`, `UFSRINGBUF` están en `n`.

## Conclusión

La cadena que hacía `modpost` fallar está cortada en los dos extremos:

- el UFS no compila `ufs-sec-feature` ni `ufs-mediatek-dbg`;
- el block layer no compila `blk-sec-*` ni `ssg-*`.

No quedan referencias directas de `blk_sec_*`/`ufs_sec_*` en objetos que se
vayan a enlazar. Si el build falla otra vez, será por otro símbolo, no por
esta cadena.
