# 98 — Android lado: que hay que mirar y que contrato no podemos romper

Todo verificado en el telefono (root). Objetivo: saber que del lado de
Android/LineageOS hay que revisar para que nuestro kernel 6.6 funcione igual
de bien que el stock, y que Improvements se pueden hacer.

## 1. Riesgos despejados (buena noticia)

| Tema | Estado real | Consecuencia |
|---|---|---|
| Bootloader | **desbloqueado** y AVB con `hashtree_disabled` (docs/03-build.md de `ruby-gki`) | un `boot.img` reempaquetado se flashea **sin re-firmar vbmeta** |
| Modulos del vendor | `/proc/modules` **vacio**; las lineas `insmod /vendor/lib/modules/*.ko` estan **comentadas** en los `.rc` | **nuestro kernel puede llevar el vermagic/srcversion que quiera**: no hay que clonar el config exacto del kernel stock para que carguen los 78 `.ko` (de hecho no cargan ninguno) |
| Device Tree | DTB 6.6 de ruby ya extraido (`work/dtb_boot/01_dtbdump_MT6877.dtb`) | no hay que portar el DT |
| Particion del kernel | el kernel que arranca va **dentro de `boot.img`** (la particion `gz` solo aparece en la lista A/B del OTA) | basta con reempaquetar `boot.img` conservando cabecera MTK, ramdisk y DTB |
| SELinux | la politica del vendor espera el kernel stock | arrancar el primer test en **permisivo** (`setenforce 0` con APatch) y luego medir `avc: denied` |

## 2. Contrato kernel <-> user space del vendor (no se puede romper)

El HAL del vendor habla con el kernel por `/proc`, `/dev`, `/sys` e ioctls
concretos. Si nuestro kernel no los expone, se rompen camara, display, carga,
USB-PD, termica o GPU **aunque el kernel arranque bien**.

### 2.1 Entradas de /proc que crea el kernel

```
displowpower   mi_display       mtk_battery_cmd   mtk_lpm
mtk_mali       mtk_mdp_debug    mtk_pm_qos        mtk_rtc
mtk_typec      mtkcooler        mtkfb             mtkfb_debug
```

`mi_display` y `mtkfb` son la API de display de MTK; `mtk_typec` la de
USB-PD; `mtkcooler` la de disipacion; `mtk_battery_cmd` la del servicio de
bateria; `mtk_mali` la de potencia de GPU.

### 2.2 Nodos de /dev

```
camera-dip  camera-dpe  camera-fdvt  camera-isp  camera-mfb
camera-rsc  camera-wpe  camera_eeprom0..4  kd_camera_hw
ccci_ioctl0..4   ccci_c2k_agps        (modem + AGPS)
gpsdl0  gpsdl1  gps_emi              (GPS DLink + EMI)
isee_tee0                            (TEE: Microtrust)
mi_display  mtk_mdp                  (display y multimedia)
```

### 2.3 Sysfs

```
/sys/class/thermal/cooling_device0..N+     (mas de 100; los usa el HAL termico)
/sys/class/typec/port0/{cdev0,cdev0_trip_point,available_policies,port0-partner}
/sys/class/power_supply/{ac,battery,bbc,bms,charger,cp_master,cp_slave,primary_chg,usb}
/sys/class/drm/card0-DSI-1/{status,modes}
/dev/socket/mnld                            (socket de MTK GNSS)
```

### 2.4 Lo que el stock **no** ofrece y si se puede arreglar

- `charge_control_limits_max_current/max_voltage` **no existen** en ningun
  nodo de `power_supply` -> `dumpsys battery` muestra `Max charging current: 0`.
  Es un hueco del driver de carga (arreglo en nuestro port).
- `debugfs` vacio: el vendor no depende de el (ninguna restriccion).

## 3. Lo que hay que mirar en el primer arranque de nuestro kernel

1. Que existan las 12 entradas de /proc y los /dev de la tabla (si falta
   `mi_display` o `mtk_typec`, el vendor se queda sin esa funcion).
2. `ls /sys/class/thermal/cooling_device* | wc -l` > 0 y coherente con el
   stock (el HAL termico enumera los cooling devices).
3. `dumpsys battery`: `status` correcto y `Max charging current` > 0.
4. `dumpsys media.camera`: que salgan los 5 dispositivos.
5. `dumpsys display`: 1080x2400 con 60/90/120 Hz.
6. `dumpsys bluetooth_manager` y `dumpsys wifi`: conectividad.
7. `logcat | grep -c "avc: denied"` (primero con `setenforce 0`, luego
   enforcing) y `dmesg | grep -c "disagrees about version of symbol"`.
8. `droidspaces check` con 0 must-have fallidos.
9. `lsmod` vacio y `/proc/modules` sin errores (no debe aparecer ningun
   `invalid module format`).

Este checklist es el que se ha incorporado a `scripts/verify-ruby.sh`.

## 4. El pstore guarda un panic de **nuestro** kernel A34 (no del stock)

`/sys/fs/pstore/` contiene `console-ramoops-0`, `dmesg-ramoops-0` y
`dmesg-ramoops-1` de un arranque anterior:

```
Panic#1 Part1
KP event: paging-init
KP hotpatch backend: framework (alias_page: ...)
init: Release specific kernel module dir 6.6.127-android15-8-abogkiA346BXXSEEZB6-4k
init: LoadWithAliases was unable to load tzdev
...
do_exit -> do_group_exit -> __arm64_sys_exit_group
```

El numero de build `abogkiA346BXXSEEZB6` es el de la **A34**: es decir, este
panic es de **nuestro kernel de prueba** (la base A34), no del stock. Dos
lecturas:

1. El panic ocurre en el `init` de primera etapa, cuando el proceso de init
   llama a `exit_group`, con el framework de hotpatch (KPM de APatch)
   activo. Hay que mirar si es el KPM el que lo provoca o si es un fallo
   real del kernel: en nuestro kernel final hay que repetir el arranque con
   APatch activo y sin el.
2. `LoadWithAliases was unable to load tzdev` -> el init de Android intenta
   cargar el modulo `tzdev` (TEEGRIS) y no lo encuentra. Con el kernel
   propio (TEEI/Microtrust) habra que ver si el init insiste y como
   afecta al arranque.

## 5. Android: mejoras de donde sale el trabajo

- **OTA**: la ROM firma `boot.img`; si flasheamos a mano, la proxima OTA
  restaura el kernel stock. Para "dejarlo listo" hay que decidir si el
  kernel propio se integra en el build de la ROM (un `BoardConfig.mk` con
  `TARGET_KERNEL_SOURCE` propio) o se documenta como kernel de pruebas
  re-flashable con `scripts/flash-ruby-slot-b.sh`.
- **Fingerprint/IR**: el kernel expone `goodix,goodix-fp` por SPI en el
  dtbo; el driver de 4.19 (`drivers/input/fingerprint/goodix_cap`) habla con
  el TEE, asi que depende de Microtrust: si el TEEI 400 no entra bien, la
  huella tampoco.
- **Termica**: 100+ cooling devices; el HAL termico y `mtkcooler` deben
  seguir viniendo del mismo driver MTK 6.6, no inventar una politica nueva.
- **Camara**: 5 sensores; los drivers imgsensor de MTK 6.6 estan, pero el
  DTS de ruby es el stock: si el kernel nuevo usa otro DTB, la camara puede
  dejar de enumerated. Por eso el DTB se reutiliza tal cual.
