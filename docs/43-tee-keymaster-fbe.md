# 43 — TEE, keymaster y FBE

## Fallo observado

El kernel 6.6 del A34 arrancó Android hasta `vold` y `keystore2`, pero no pudo
descifrar `/data`:

```
keystore2 Keystore createOperation returned service specific error: -1000
vold: decryptWithKeystoreKey failed
vold: read_key failed in mountFstab
vdc: cryptfs init_user0 Failed
reboot: Restarting system with command 'recovery'
```

No hay corrupción de datos: el slot A sigue arrancando con la misma `/data`.
El fallo es la cadena **TEE → keymaster → keystore2 → FBE**.

## Módulos TEE del A34

```
tzdev.ko
gz_trusty_mod.ko
gz_ipc_mod.ko
gz_irq_mod.ko
gz_log_mod.ko
gz_virtio_mod.ko
gz_tz_system.ko
iommu_gz.ko
mtk_sec_heap.ko
trusted_mem.ko
gz_main_mod.ko
tee.ko
teeperf.ko
```

Dependencias comprobadas:

```
iommu_gz       -> gz_tz_system
gz_tz_system   -> gz_ipc_mod, gz_trusty_mod, tzdev
trusted_mem    -> gz_tz_system, iommu_gz, tzdev
gz_main_mod    -> gz_tz_system, gz_trusty_mod, gz_ipc_mod, mtk_sec_heap, trusted_mem
rpmb-mtk       -> tzdev, ufs-mediatek-mod-ise, rpmb   (no incluido aún)
```

El initramfs de prueba se queda en ~21 MB tras `strip --strip-debug`, y con
`Image.gz` cabe en el boot image de ruby.

## APatch y el wrapper

APatch parchea el kernel y ejecuta su hook antes de `first-stage`:

```
KP event: pre-init-first-stage
KP event: post-init-first-stage
```

Eso **se salta el `/init` wrapper** del ramdisk. Por eso el watchdog del wrapper
no se ejecuta en una imagen parcheada con APatch.

Para pruebas de kernel/TEE se usa una imagen **sin APatch** con:

```
/init -> wrapper
/bctool -> binario estático que escribe slot A
watchdog de 90 s
```

Cuando el kernel ya arranque Android de forma estable se añade APatch y se
configura su hook `pre-init` para el retorno, o se usa `service.d` una vez que
Android sí llegue a `boot_completed`.

## Estado actual

```
slot A
Android 17
sys.boot_completed=1
APatch root con superkey vacía
```

Imagen TEE sin APatch preparada:

```
/tmp/stock-tee.img
sha256 a98021e10de3d28e7fddbef3792e84c420f16af39c2eeeb9d0c2635ce56852f9
```

No se flashea hasta probar el wrapper sin APatch y confirmar que el watchdog
devuelve a A.
