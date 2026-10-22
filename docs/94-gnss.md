# 94 — GNSS/GPS de ruby: de donde sale el driver

## Como funciona el GPS en ruby

Nodos y servicios en el telefono (verificado en el dispositivo):

```
/dev/gpsdl0   /dev/gpsdl1     # GPS D-Link (MCU)
/dev/gps_emi                     # interfaz EMI
/dev/ccci_c2k_agps               # AGPS por CCCI
/dev/stpbt                       # sensor hub (STP) para BT
servicio: vendor.gnss-default    # demonio GNSS de MTK
servicio: agpsd
```

Es el stack **consys** de MTK: el driver del kernel (STP/DLink) habla con el
firmware del GPS en el micro de MTK a traves del SCP y expone `/dev/gpsdl*`;
el demonio `vendor.gnss-default` (vendor) habla con ese driver.

## Fuentes disponibles

| Origen | Contenido | Version |
|---|---|---|
| `sources/ruby-4.19/drivers/misc/mediatek/connectivity/gps/` | `gps_stp`, `gps_pwr`, `gps_scp`, `data_link`, `init.gps_drv.rc` | 4.19 (exactamente el de ruby) |
| `mt6897-devs/android_vendor_mediatek_kernel_modules` -> `connectivity/gps/` | `gps_stp`, `gps_mcudl`, `gps_pwr`, `gps_scp`, `data_link`, `fw_log` | **6.6**, layout de modulos de MTK (2026-09) |
| `NothingOSS/android_kernel_modules_nothing_mt6878` -> `connectivity/gps/gps_mcudl` | variante DLink (la que usa ruby: `/dev/gpsdl*`) | 6.6 |

El arbol publico de MTK 6.6 de MT6877 (Volla) **no** trae el driver GNSS:
solo el `drivers/gnss` generico de upstream. El driver consys de MTK se
distribuye aparte, como modulos de vendor (`vendor/mediatek/kernel_modules/
connectivity/gps/...`), y por eso no aparece en los repos de kernel.

## Plan

1. Partir del 6.6 (`mt6897-devs`) por ser la misma generacion de drivers
   MTK 6.6; usar el 4.19 de ruby como referencia de comportamiento (los
   nombres de nodos, el `init.gps_drv.rc` y las props del DTS son los de
   ruby).
2. Montarlo como modulos del device modules tree:
   `drivers/misc/mediatek/connectivity/gps/` con su Kconfig/Makefile.
3. El DTS de ruby ya trae los nodos (esta en el DTB 6.6 extraido), asi que
   no hay que tocarlo.
4. El firmware del GPS (`.bin` de MTK) lo tiene el `vendor` del telefono:
   `/vendor/firmware/gnss` o similar -> no hay que tocarlo.
5. El HAL de MTK (`gnss` service) ya es del vendor y habla con el driver
   estandar.

## Criterio de aceptacion

```
su -c 'ls -l /dev/gpsdl0 /dev/gps_emi'   # nodos del driver
su -c 'dmesg | grep -i stp'               # STP/GPS inicializado
dumpsys location                          # provider GPS presente
```
Y en la practica: fix GPS en exterior (la UI debe mostrar posicion).
