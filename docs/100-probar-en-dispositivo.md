# 100 — Poner el kernel 6.6 de ruby en el dispositivo (y volver atrás)

Todo el proceso está pensado para **no depender de un PC externo**: el
teléfono se auto-revierte al slot A si el kernel no arranca.

## 0. Qué hay que tener

```sh
# 1) un build verde del kernel de producto (display + tactil + carga + TEE)
gh workflow run -R criollojoel10/rubyx-kernel66-lab build-ruby-full.yml --ref main
# el workflow falla si falta cualquiera de los 9 modulos nuevos

# 2) descargarlo
gh run download -R criollojoel10/rubyx-kernel66-lab <run> -n ruby-full -D artifacts/
```

## 1. Montar el boot.img

```sh
scripts/build-ruby-boot.sh --ci-run <run> --out /tmp/ruby-6.6.img
```

Que hace:

1. coge `Image.gz` y los `.ko` de ruby del artefacto;
2. mete los `.ko` en el ramdisk stock (`lib/modules` + `modules.load`);
3. conserva el **DTB 6.6 de ruby** (`dts/ruby-stock-base.dtb`), que es el
   mismo que usa el kernel stock: el overlay `dtbo` de la particion
   `dtbo` se aplica igual que siempre;
4. genera el `boot.img` con el layout y el pie AVB del `boot_b` original.

Comprobaciones antes de flashear:

```sh
sha256sum /tmp/ruby-6.6.img
ls -l /tmp/ruby-6.6.img        # 128 MB, como el original
```

## 2. Flashear en el slot B con retorno automatico

```sh
scripts/run-slot-b-test.sh /tmp/ruby-6.6.img
```

El script:

1. copia la imagen al telefono (`/sdcard`) y verifica el hash;
2. la escribe en `boot_b` y comprueba el readback;
3. marca el **slot B con `tries=1`** (si el kernel no arranca, el
   bootloader vuelve a A en el siguiente reinicio);
4. reinicia y monitoriza el arranque.

El telefono esta en **Termux con root APatch** (`su -c id` -> uid=0) y el
host se conecta por `ssh termux`.

## 3. Que mirar si arranca

```sh
scripts/verify-ruby.sh          # resumen de todo
```

En detalle:

```sh
ssh termux 'su -c "dmesg | grep -iE \"teei|ut_keymaster|fts|m16|dsi|panel\""'
ssh termux 'su -c "ls /dev/teei_client /dev/ut_keymaster /dev/tz_vfs"'
ssh termux 'su -c "cat /sys/class/drm/card0-DSI-1/status"'
ssh termux 'su -c "getevent -lt | head -20"'          # tactil
ssh termux 'su -c "ls /sys/class/power_supply"'        # carga
ssh termux 'su -c "/data/local/Droidspaces/bin/droidspaces check"'
ssh termux 'su -c "dumpsys battery"'
```

Criterios:

| Subsistema | Como se comprueba |
|---|---|
| TEE | `dmesg` con `[tz_driver] TEEI UT` y `/dev/ut_keymaster` presente |
| FBE | `init_user0` sin error (sin `Can't load Android system`) |
| Display | `/sys/class/drm/card0-DSI-1/status` = connected y sin errores de DSI |
| Tactil | `getevent` con eventos de multitáctil (ABS_MT_SLOT) |
| Carga | `dumpsys battery` con `status: charging` y el nivel subiendo |
| GPS | `dumpsys location` con provider GPS y fix |
| Droidspaces | `droidspaces check` sin features obligatorias ausentes |

## 4. Si no arranca

- El bootloader vuelve al slot A solo (tries=1). No hay que hacer nada.
- El `pstore` de la particion `misc` guarda el log del kernel que fallo:
  ```sh
  scripts/read-pstore.sh
  ```
- Con APatch instalado, el `init` de Android B no llega a ejecutar
  `service.d`, asi que la autorreparacion de `service.d/99-ruby-selfheal.sh`
  no ayuda en ese caso: por eso las imagenes de test llevan el wrapper
  `port/device/selfheal/first-stage-init.sh`, que arma un watchdog **antes**
  de `exec /system/bin/init` y vuelve a A si Android no confirma.

## 5. Dejar el kernel de forma permanente

Cuando el kernel 6.6 arranque bien y todo funcione:

```sh
scripts/mtk-slot.py set b --write     # slot B sin tries=1
```

y a partir de ahi se puede flashear el `boot_a` con la imagen buena
(slot A) y dejar el telefono con 6.6 de forma estable.
