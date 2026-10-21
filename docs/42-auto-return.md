# 42 — Auto-retorno desde slot B

Objetivo: probar kernels nuevos sin depender de un PC ni de fastboot.

## Capas de recuperación

1. **Bootloader**: slot B se marca con `tries=1`. Si el kernel no llega a
   arrancar Android, LK vuelve a A.
2. **APatch en el boot de prueba**: la imagen nueva se parchea con
   `kptools` y superkey vacía, para que el Android del slot B tenga root y
   `service.d`.
3. **Servicio de auto-retorno**: `/data/adb/service.d/99-ruby-selfheal.sh`.
   Si arranca `_b`, espera a `sys.boot_completed`, registra kernel/slot y
   escribe el slot A; después reinicia.
4. **Marker `keep-b`**: si existe `/data/adb/ruby/keep-b`, el servicio no
   vuelve a A. Sirve para una sesión manual deliberada.

## Instalación

```sh
scp port/device/selfheal/mtk-slot-local.py termux:/sdcard/
scp port/device/selfheal/99-ruby-selfheal.sh termux:/sdcard/
ssh termux 'su -c "
  mkdir -p /data/adb/ruby
  cp /sdcard/mtk-slot-local.py /data/adb/ruby/
  cp /sdcard/99-ruby-selfheal.sh /data/adb/service.d/
  chmod 755 /data/adb/ruby/mtk-slot-local.py /data/adb/service.d/99-ruby-selfheal.sh
  /data/data/com.termux/files/usr/bin/python3 /data/adb/ruby/mtk-slot-local.py status
"'
```

## Parche APatch

El `kpimg` está en:

```
/data/data/me.bmax.apatch/check/kpimg
```

Y el boot de prueba se parchea en el teléfono:

```sh
kptools -p -i /sdcard/boot-test.img \
  -k /data/data/me.bmax.apatch/check/kpimg \
  -s "" -o /sdcard/boot-test-apatch.img
```

El `-s ""` deja la superkey vacía. El resultado conserva el header v2 y el
footer AVB; `unpack_bootimg` lo valida.

## Prueba segura

1. `boot-test-apatch.img` en slot B con `tries=1`.
2. Al arrancar B, APatch ejecuta `99-ruby-selfheal.sh`.
3. El script escribe el slot A y reinicia.
4. Si B no arranca, LK ya vuelve a A por `tries=1`.

No se debe flashear un boot de prueba sin APatch y sin este servicio.
