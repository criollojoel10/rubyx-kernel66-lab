# 21 — Prueba de slot B con retorno automático a Android

## Objetivo

Probar el `Image` 6.6.127 + 11 módulos en `boot_b`, escribir marcas en pstore
y **volver solo a Android en slot A**, sin depender de fastboot de PC.

## Estructura A/B de MTK: validada

En `misc`, offset 2048, hay un `bootloader_control` de 32 bytes:

```
offset 0   slot_suffix[4]   "_a\0\0"
offset 4   magic            "BCAB" (0x42414342)
offset 8   version          1
offset 9   nb_slot          2
offset 12  slot A           0x9f -> prio 15, tries 1, successful 1
offset 14  slot B           0x9e -> prio 14, tries 1, successful 1
offset 28  crc32_le(first 28 bytes)
```

Comprobado en el dispositivo:

```
suffix=_a magic=0x42414342 crc=0xc5020ee9 (stored == calc)
```

Fuentes que coinciden:

- `Advnirr/twrp_device_xiaomi_degas/tools/slot_switch.py` — offset 2048,
  tamaño 32, CRC en 28..31.
- `slimbootloader/AbSupport.h` — struct `AB_BOOT_INFO`, magic `BCAB`,
  prioridad/tries/successful.
- `u-boot/boot/android_ab.c` — CRC32 sobre los bytes anteriores al campo.

La HAL `IBootControl` de Android reporta `getNumberSlots=0` de forma extraña,
pero **no la usamos**: escribimos el struct directamente.

## Watchdog y retorno a Android

Diseño del PID 1 (`port/diag/diag-init.c`):

1. Monta devtmpfs/proc/sys.
2. Abre `/dev/kmsg` y `/dev/pmsg0`; registra `RUBYDIAG ...`.
3. Carga los 11 `.ko` de `/lib/modules/modules.load` con `finit_module`.
4. Registra `MODULE_OK/FAIL` por módulo.
5. Arma `/dev/watchdog` a 60 s.
6. Espera 20 s.
7. Escribe el struct A (`_a`, A prio 15/tries 7/ok 1, B prio 14/tries 7/ok 0).
8. `reboot` → Android slot A.

Capas de seguridad:

- `alarm(90)`: si el init se bloquea, hace lo mismo.
- `/dev/watchdog` 60 s: si el kernel se cuelga después de cargar `mtk_wdt`,
  el hardware resetea.
- Slot B se marca con **tries=1**: si el kernel no llega a init, el
  bootloader agota el intento y vuelve a A (prioridad 14, successful=1).
- `panic=10 panic_on_oops=1`: un pánico reinicia.

Riesgo residual: un cuelgue **antes** de que el init arme el watchdog no se
puede recuperar solo; ahí queda Fastboot de PC.

## Artefactos preparados

```
boot_b stock      device/backups/boot_b-stock.img
                  134217728 B  sha256 c9d6ad0d...  (== boot stock)
misc stock        device/backups/misc-stock.img
                  4194304 B   sha256 a1a43d22...
BCB stock         device/backups/misc-bcb-stock.bin
                  32 B        sha256 ebcec16f...

diag stock DTB    /tmp/ruby-diag-stockdtb.img
                  134217728 B  sha256 1c557cd3...
diag ruby DTB     /tmp/ruby-diag-rubydtb.img
                  134217728 B  sha256 e912c076...

kernel            Image.gz  sha256 b135740d...
initramfs         2326432 B sha256 29d4ac57...
init              estático aarch64
```

El primer test usa el **DTB stock** para aislar kernel/módulos; el segundo usa
`dts/ruby-minimal.dtb`.

## Cómo se construyó

```
aarch64-linux-gnu-gcc -static -Os -o /tmp/ruby-diag-init port/diag/diag-init.c
./scripts/build-diag-initramfs.py /tmp/ruby-diag-init port/modules/closure \
    /tmp/ruby-diag-initramfs.cpio.gz
./scripts/build-diag-boot.py --original device/backups/boot_b-stock.img \
    --kernel Image.gz --initramfs /tmp/ruby-diag-initramfs.cpio.gz \
    --out /tmp/ruby-diag-stockdtb.img
```

El boot image conserva del `boot_b` stock:

- header v2, páginas 2048;
- kernel load `0x40080000`, ramdisk `0x51100000`, tags/DTB `0x47c80000`;
- tamaño 128 MiB y **AVB footer/vbmeta**;
- el hash AVB ya no coincide, pero el bootloader real está unlocked
  (`androidboot.vbmeta.device_state=unlocked`, `veritymode=disabled`).

## Herramientas en Termux

Verificado/instalado:

```
openssh 10.6p1-2
coreutils 9.12
util-linux 2.42.4
python3
```

`su -c dd`, `sha256sum`, `blockdev`, `base64` funcionan.

## Procedimiento (todavía NO ejecutado)

### 1. Verificar todo

```
sha256sum device/backups/boot_b-stock.img
./scripts/mtk-slot.py status
```

### 2. Poner slot B activo con un solo intento

```
./scripts/mtk-slot.py set b --write
```

Esto escribe 32 bytes en `misc@2048` y verifica la lectura. No toca `boot_b`
todavía.

### 3. Escribir la imagen de diagnóstico en boot_b

```
scp /tmp/ruby-diag-stockdtb.img termux:/sdcard/ruby-diag.img
ssh termux 'su -c "dd if=/sdcard/ruby-diag.img of=/dev/block/by-name/boot_b bs=4M conv=fsync"'
```

Verificar hash de los primeros 128 MiB contra el artefacto.

### 4. Reiniciar

```
ssh termux 'su -c reboot'
```

El bootloader arranca B. El init registra etapas y a los ~20 s vuelve a A.

### 5. Leer pstore

```
./scripts/read-pstore.sh
```

Archivos:

```
/sys/fs/pstore/console-ramoops-0
/sys/fs/pstore/pmsg-ramoops-0   (marcas RUBYDIAG)
```

### 6. Si no vuelve Android

- Si el kernel no llegó a init: B tiene tries=1; debería agotarse y bootear A.
- Si no lo hace: PC fastboot:

```
fastboot flash boot_b device/backups/boot_b-stock.img
fastboot --set-active=a
fastboot reboot
```

## Criterio de éxito

```
RUBYDIAG PID1_START
RUBYDIAG MODULE_OK clk-common.ko
...
RUBYDIAG MODULES_DONE
RUBYDIAG RETURN_SLOT_A_OK
```

y Android A arranca solo. Sin esas marcas, no se declara nada.

## Resultado de la primera ejecución (2026-10-20)

La prueba se ejecutó y el kernel arrancó en B. El detalle está en
`docs/22-resultado-test1.md`.

Resumen:

- 7 módulos cargaron: `aee_aed`, `clk-common`, `clk-mt6877`,
  `mt6359p-regulator`, `mtk-pmic-wrap`, `mtk-spmi-pmic`, `mtk_wdt`;
- `pwrap probe success` y `clk_mt6877_top_probe init end`;
- pstore de consola: 36 365 B;
- el init no pudo escribir `misc`, pero el bootloader volvió a A porque B
  tenía `tries=1`;
- dispositivo restaurado a `boot_b`/`misc` stock.

La siguiente imagen (`/tmp/ruby-diag2-stockdtb.img`, sha256
`55e5b815...`) corrige pmsg, watchdog, fallback de `misc` y logs de módulos.
No se ha flasheado.
