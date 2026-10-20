# 20 — Referencia postmarketOS: Redmi Note 11 Pro (pissarro, MT6877)

## Repo encontrado

```
https://github.com/Nxages/redmi-note-11-pro-postmarketos-server
commit 4021a50eab1bf58a2f4fedb23b5cec13e0f7904e
```

No es un repo oficial de postmarketOS: es un port/field report de un usuario
sobre `pissarro` (Redmi Note 11 Pro, MT6877, Dimensity 920). Aun así es la
referencia práctica más cercana a ruby.

## Qué hace

- Arranca un kernel Linux propio desde **`boot_b`**.
- Guarda el rootfs ext4 en un **rango de `super`** (4 GiB), no en una
  partición propia.
- Initramfs con PID 1 estático (`src/initramfs/persistent-init.c`) que:
  - monta el rootfs desde `super`;
  - crea un gadget USB ACM (`/dev/ttyGS0`) para SSH de rescate;
  - escribe marcas de etapa en `/dev/kmsg` y **`/dev/pmsg0`**;
  - watchdog de 600 s que vuelve a Fastboot si no se confirma el boot.
- `tools/build-boot-image.py` reutiliza del `boot_b` original:
  - layout, DTB, cmdline y **AVB footer**;
  - elimina `root=`, `rdinit=`, `init=`, `panic=`,
    `skip_initramfs`, `androidboot.force_normal_boot=`;
  - añade `root=/dev/ram rdinit=/init panic=10 selinux=0`;
  - deja la imagen del **mismo tamaño** que la partición y conserva el
    vbmeta/footer, aunque el hash ya no coincida (solo con bootloader
    desbloqueado).

## Lo que sirve para ruby

### 1. `boot_b` es el camino

El repo confirma que un MT6877 con Virtual A/B arranca desde `boot_b` y que
`fastboot boot` puede fallar (`usb_read failed (31)`); ellos tuvieron que
flashear `boot_b`. Nuestro `boot_b` existe, está respaldado y coincide con el
boot stock (`sha256 c9d6ad0d...`).

### 2. Initramfs mínimo con marcas de etapa

Su PID 1 escribe:

```
<3>PMLINUXROOT BOOT_STAGE=...
```

en `/dev/kmsg` y `/dev/pmsg0`. En ruby:

```
/dev/pmsg0        existe (mode 0620, root:log)
/sys/fs/pstore/   console-ramoops-0
```

Eso permite dejar un rastro legible en pstore aunque Android no arranque.
No hace falta montar Android para leerlo: se reinicia al slot A/stock y se
lee `/sys/fs/pstore/pmsg-ramoops-0` o `console-ramoops-0`.

### 3. USB serial de rescate

Su init crea un gadget ACM (`1d6b:0104`) y sirve SSH por `/dev/ttyGS0`. Es una
alternativa a UART física, pero requiere que el kernel tenga USB gadget
(`configfs`, `dwc3`/`mtu3`) y no está en nuestros 11 módulos actuales.

### 4. Consola

Su cmdline usa:

```
console=ttyMT3,921600n1
```

No `ttyS0`. En ruby el stock usa `ttyS0`; para el diagnóstico conviene probar
ambos (`console=ttyS0,... console=ttyMT3,... earlycon`).

## Lo que NO copiamos

- **Rootfs en `super`**: no lo queremos; el objetivo es Android con nuestro
  kernel, no Linux en el rango de OTA.
- **Offsets de `deviceinfo`**: su base es `0x40000000`, kernel offset
  `0x00080000`, ramdisk `0x11100000`; ruby usa `0x40078000`, `0x00008000`,
  `0x11088000`. No se copian; se leen del `boot_b` real.
- **Kernel 4.14**: su port usa el árbol `hydrogen` 4.14; nosotros vamos con
  6.6.127 del A34.

## Cómo adaptarlo a nuestro diagnóstico

1. Tomar el `boot_b` stock como plantilla (header v2, DTB, cmdline, AVB).
2. Escribir un PID 1 mínimo que:
   - abra `/dev/kmsg` y `/dev/pmsg0`;
   - registre `BOOT_STAGE=...`;
   - cargue los 11 `.ko` con `finit_module`;
   - registre el resultado de cada uno;
   - espere y reinicie a bootloader para volver a Android.
3. Empaquetar initramfs `newc` + gzip, no el ramdisk Android completo.
4. Mantener el tamaño/AVB footer del `boot_b` original.
5. Leer pstore tras volver a Android.

Eso es más informativo que el boot actual (ramdisk Android + `init` stock),
porque si `init` no llega a ejecutarse no hay marcas propias; solo el log de
consola del kernel.

## Comandos útiles del repo

```
python3 tools/build-boot-image.py \
  --original boot_b.img --kernel Image.gz --init out/init \
  --mkbootimg path/to/mkbootimg.py --out boot-linux.img
```

```
fastboot flash boot_b boot-linux.img
fastboot reboot
```

```
ssh -o "ProxyCommand=python3 tools/serial-ssh-proxy.py /dev/ttyACM0" \
    -o HostKeyAlias=redmi-linux-rootfs root@rescue
```

## Conclusión

El repo valida la estrategia de `boot_b`, el initramfs propio y el uso de
pstore/pmsg para diagnosticar. No valida `super` para ruby ni un kernel 6.6,
pero su `build-boot-image.py` y su PID 1 son la mejor plantilla para la
siguiente imagen de diagnóstico.

## Nota: el “locked” es spoof de APatch

En userspace:

```
getprop ro.boot.vbmeta.device_state  -> locked
getprop ro.boot.veritymode           -> enforcing
getprop ro.boot.verifiedbootstate     -> green
```

Pero el cmdline real que pasa el bootloader dice:

```
androidboot.vbmeta.device_state=unlocked
androidboot.veritymode=disabled
androidboot.verifiedbootstate=orange
```

APatch está ocultando el estado real para Play Integrity. El bootloader está
**abierto** y con root APatch. Por eso:

- un `boot_b` modificado no es rechazado por AVB;
- se puede escribir `boot_b` con `dd` desde root;
- el único riesgo real es quedarse sin usuariospace para volver al slot A,
  no la firma.
