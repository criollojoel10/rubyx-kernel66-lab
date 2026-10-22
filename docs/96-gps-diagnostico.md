# 96 — GPS a fondo: el driver funciona, el bus de conectividad no

Diagnostico hecho con una sesion GPS real en el telefono (con los logs de GPS
desocultados: `resetprop ro.vendor.mtk_log_hide_gps 0`).

## 1. Lo que hace bien el driver

El driver **GDL (GPS Data Link)** de MTK esta compilado y funciona:

```
21:09:07.603 GDL gps_each_device_open: major = 500, minor = 0
21:09:07.604 GDL gps_dl_hw_gps_common_on: SUPPORT:MT6877: poll_ver = 0x02060002,
                                       adie_ver = 0x00006635 is ok
21:09:07.605 GDL gps_dsp_fsm: old_st=OFF , evt=FUNC_ON , new_st=ON
21:09:07.605 GDL gps_dsp_fsm: old_st=ON  , evt=RST_DONE, new_st=RST
21:09:07.605 GDL state change: OPENING -> OPENED
```

El chip arranca, la FSM pasa a `RST`, el DMA se configura sobre
`conn_gps_base` (0x18C00000) y a los 35 s se apaga limpiamente:

```
21:09:42.6xx GDL conninfra@(_conninfra_core_drv_status_dump):
             [Conninfra Pwr Off]: BT:[on] FM:[off] GPS:[off] WIFI:[on] CONNINFRA:[off]
21:09:42.851 GDL gps_dsp_fsm: old_st=RST , evt=FUNC_OFF, new_st=OFF
```

O sea: **el driver del kernel no es el problema**. El problema es que la
sesion se aborta a los ~35 s desde espacio de usuario.

## 2. La sesion se aborta

```
21:09:42.622 GDL gps_dl_link_wait_on: signaled by -512     (x3, pids 20363/20365/20368)
```

`-512` es `ERESTARTSYS`: la espera se interrumpe porque **el daemon MNLD/HAL
cierra el dispositivo**. El HAL de MTK da por agotado el tiempo de espera del
chip y aborta. Consistente con que Google Maps este al 22 % de CPU todo el
 rato (reintenta la sesion en bucle) y con que no llegue ningun fix.

## 3. La pista fuerte: el bus de conectividad en timeout permanente

```
[CONN_BUS_C]ahb_apb_timeout:[0x18004004][0x00006040][0x18004000][0x00000002]...
```

- **211 eventos y subiendo, uno por segundo, de forma continua** (medidos
  entre los timestamps 11953 y 12182 del dmesg).
- Todos los registros estan en el bloque **conninfra** (base 0x18000000):
  0x18004004, 0x18001004, 0x1800401c, 0x18005128, 0x18070034, 0x18052841.
- El que los imprime es el driver de WLAN (pid 6163), que acumula **78 s de
  CPU de sistema** solo en sondeos fallidos.
- En la misma ventana, WLAN se queja 150 veces de `No free SwRfb!` (pool de
  buffers de RX agotado) y de `qmFlushTimeoutReorderBubble`.

Por que importa para el GPS: el GPS y el WLAN **comparten el dominio de
potencia/clock de conninfra**. Al cerrar la sesion de GPS el driver hace
`conninfra_pwr_off` ("CONNINFRA:[off]") mientras WLAN sigue activo
("WIFI:[on]"), y a partir de ahi WLAN no obtiene respuesta de esos
registros: el timeout es permanente, no un evento puntual.

Hipotesis: o el firmware de WLAN no responde a esos accesos (desajuste
driver/firmware), o el estado de power/clock de conninfra queda mal tras el
`conninfra_pwr_off` de la sesion GPS.

## 4. Falso positivo descartado: MD2GPS_REG

```
GDL-0[E:1] gps_each_device_ioctl_inner: Can't get MD2GPS_REG in this platform
```

El driver lee la propiedad DT `b13b14-status-addr` (registro de estado
modem<->GPS). **El DTB 6.6 de ruby no la tiene**, pero tampoco la tiene el
DTS de referencia de MTK para mt6877 (`mt6877.dts`); solo aparecen en
`mt6899.dts` y `mt6991.dts` (0x1c000008). En este SoC es normal y no es la
causa: el probe del driver lo tolera y el GPS arranca igual.

## 5. Que hacer

1. **Aislar si el timeout de conninfra es causa o consecuencia**: abrir una
   sesion GPS con el WiFi **desactivado** (modo avion) y ver si el GPS logra
   fix. Si con WiFi off hay fix, el culpable es el reparto de conninfra.
2. **Mirar el firmware de WLAN**: `/vendor/firmware/conninfra` y
   `/vendor/bin/hw/...` comparando version con la que espera el driver.
3. En nuestro kernel 6.6: portar el driver GDL (esta en
   `sources/ruby-4.19/drivers/misc/mediatek/connectivity/gps/data_link/`) y
   revisar el reparto de power de conninfra (que el GPS no apague conninfra
   con WLAN activo) antes de dar el GPS por cerrado.
4. Vigilar `ahb_apb_timeout` y `No free SwRfb` en el kernel propio: si
   aparecen, es que el mismo problema viene de serie.
