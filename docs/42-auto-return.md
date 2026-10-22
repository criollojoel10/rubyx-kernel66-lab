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

## Resultado real de la primera prueba APatch

Tras el fallo de módulos, un segundo intento con `modules.dep` llegó más lejos
pero Android B entró en **recovery**:

```
Can't load Android system.
reason: init_user0 failed
```

El recovery no ejecuta `service.d`, así que el selfheal de Android no puede
actuar ahí. El usuario salió con “Try again / reboot system now” y volvió a A;
no se hizo factory reset.

Para evitarlo, la imagen de test debe llevar un `/init` de primera etapa que
arme un watchdog **antes** de `exec /system/bin/init` y vuelva a A si Android
no confirma. Ese wrapper está en `port/device/selfheal/first-stage-init.sh`.


Se flasheó `stock-modules-apatch.img` (sha256
`59b5f01d3fa3f8748be1e79ffd97d2ce7bbb84a0efe28b2cd7264233c18fd8c7`)
en B con `tries=1`.

El kernel nuevo arrancó y APatch ejecutó `KP event: post-kernel-init`, pero
el `init` stock abortó antes de Android:

```
init: LoadWithAliases was unable to load aee_aed, tried: aee_aed
init: Failed to load kernel modules
init: InitFatalReboot: signal 6
```

LK volvió solo al slot A. El dispositivo quedó en Android 17 con
`sys.boot_completed=1` y slot `_a`, sin usar laptop.

El fallo no es del kernel ni de APatch: es del `modules.load`/carga de módulos
del ramdisk stock. El bootloader sí demostró la capa de recuperación.

