# 95 — Analisis del kernel 6.6 stock de ruby: que falla y que mejorar

Analisis hecho en el telefono (APatch root, solo lectura salvo dos acciones
marcadas). Config completa del stock descargada a
`evidence/ruby-stock-6.6.config` (8626 lineas).

## 1. Lo que funciona bien

| Subsistema | Estado real |
|---|---|
| Display | 1080x2400, 3 modos (60/90/120 Hz), HDR types 2/3/4, modo activo 120 Hz, DRM `card0-DSI-1` connected |
| Camara | 5 dispositivos (3 normales) expuestos a la API |
| Almacenamiento | UFS con `SCSI_UFS_MEDIATEK`, EROFS/F2FS/ext4, ZRAM 4,5 GB |
| WiFi | conectado (5745 MHz), BT activo |
| Termica | 33,8 C, sin throttling |
| Red | IPv6, WireGuard, netfilter, bridge/veth |
| Android | arranca y `sys.boot_completed` |

## 2. GPS: el driver esta pero la sesion nunca arranca

Cadena real: **HAL AIDL (Gnss) -> MNLD (daemon) -> driver del kernel**.

Lo que se ha comprobado:

- El driver del kernel **esta compilado** (built-in): existen `/dev/gpsdl0`
  (chr 499), `/dev/gpsdl1`, `/dev/gps_emi` (chr 500), `/dev/stpbt` y las clases
  `/sys/class/{gpsdl0,gpsdl1,gpsemi,stpbt,scp,gnss}`.
- El HAL AIDL **se registra bien**:
  `AIDL Gnss successfully register service: android.hardware.gnss.IGnss/default`.
- El daemon `mnld` (pid 1299) y `mtk_agpsd` viven y hablan por
  `/dev/socket/mnld`.
- **Pero `/sys/class/gnss/` esta vacio** y los dispositivos de la clase no
  tienen symlink `device` ni atributos: no hay sesion de chip abierta.
- En `dmesg` **cero mensajes** de gnss/gps/stp/consys: el driver no llega a
  hablar con el chip (el GPS de MT6877 corre en el SCP).
- En logcat solo aparece la parte de **AGPS/RIL** (`GnssHAL_AGnssRilInterface`,
  `MNL2AGPS`): nunca un "start session" ni "chip version".
- Dos timeouts del SCP en todo el arranque:
  `Error: scp_ipidev IPI 11 timeout` (coincide con un reinicio del audio SCP
  `snd_scp_ultra`, que cicla estados 0->1->2->3).
- 114 timeouts del bus de conectividad: `[CONN_BUS_C]ahb_apb_timeout:...`.

Diagnostico bloqueante: **los logs de GPS estaban ocultos** por
`ro.vendor.mtk_log_hide_gps=1`. Ya se ha puesto a 0 (resetprop) y se ha
reiniciado `vendor.gnss-default`; con los logs visibles se podra pedir un fix
y leer la FSM de MNLD para saber si falla el envio al SCP (`hal2mnl` ->
`gps_mcudl`/`stp`) o la respuesta del firmware.

Lo que hay que traer al kernel 6.6: el driver consys de MTK
(`gps_mcudl` + `gps_stp` + `gps_scp` + `data_link`), ver `docs/94-gnss.md`.

## 3. Carga: los limites no se exponen

```
dumpsys battery:
  Max charging current: 0
  Max charging voltage: 0
  status: 2 (charging)  level: 22  voltage: 3987  temperature: 338
```

En `/sys/class/power_supply/` hay `ac, battery, bbc, bms, charger, cp_master,
cp_slave, primary_chg, usb`, pero **no existen** `charge_control_limits_max_current`
ni `..._max_voltage` en ningun nodo, y `primary_chg`/`usb` se detectan como
`USB_HVDCP` (carga rapida negociada) sin que el kernel exponga los limites.
Android no puede gestionar la potencia de carga.

Arreglo: en el puerto de carga (4.19 -> 6.6) exponer los limites
(`charge_control_limits_max_current/max_voltage`) y el estado de los canales
master/slave (`cp_master`, `cp_slave`).

## 4. Conectividad: buffers de RX de WLAN agotados

150 veces `No free SwRfb!` (pool de buffers de RX de WLAN agotado) junto con
los 114 `ahb_apb_timeout` del bus de conectividad. No rompe la conexion
(WiFi conectado y estable), pero es sintoma de presion de CPU o de un pool
pequeno; conviene vigilarlo en el kernel propio.

Ademas, `Tethering: [BpfCoordinator] WARN Failed to update conntrack entry ...
ENOENT` en bucle: es del netd del vendor (BPF), no del kernel, pero delata
filtros de netfilter del usuario que no siempre encuentran la entrada.

## 5. Droidspaces: lo que falta en el stock

```
Falta (must-have):  PID_NS  IPC_NS  USER_NS  SYSVIPC  POSIX_MQUEUE
                    CGROUP_PIDS  CHECKPOINT_RESTORE  NETFILTER_XT_MATCH_ADDRTYPE
Opcionales:         MACVLAN  MACVTAP  IPVLAN  VXLAN  GENEVE
```

Y un detalle importante: `FAIR_SCHED` y `CFS_BANDWIDTH` estan **desactivados**
aunque `CGROUP_SCHED=y` y `CGROUP_CPUACCT=y` esten activos. Sin
`FAIR_SCHED`/`CFS_BANDWIDTH` los limites de CPU por cgroup no funcionan, que
es justo lo que usa Droidspaces para `--cpus`. El parche kABI oficial de
Droidspaces deja estos simbolos reservados; hay que confirmarlo contra el
parche y regenerar la baseline.

## 6. Rendimiento: que se puede mejorar

| Opcion | Stock | Comentario |
|---|---|---|
| `LTO_CLANG` / `LTO_THIN` | off | sin optimizacion de link time (el banner dice "+lto" pero la config manda) |
| `KSM` | off | sin deduplicacion de paginas |
| `NO_HZ_FULL` | off | solo tickless idle, no full dynticks |
| `UNIVERSAL_SCALING` / `ENERGY_PERF_BIAS` | off | sin el ajuste EAS/uclamp de MTK: se pierde afinidad de CPU y politica termica fina |
| `NET_CLS_CGROUP` | off | sin clasificar trafico por cgroup (mal impacting en bateria) |
| `NUMA_BALANCING` | off | irrelevante en un movil |
| `LRU_GEN` (MGLRU) | on | bien: LRU multigeneracion |
| `ZRAM` | on | bien |
| `PSI` | on | bien |
| `HZ_250` | on | correcto para movil |
| `PREEMPT` + `NO_HZ` | on | correcto |
| `CFI_CLANG`, `SHADOW_CALL_STACK` | on | bien |
| `RANDOMIZE_BASE`, `FORTIFY_SOURCE`, `STACKPROTECTOR_STRONG` | on | bien |

## 7. Seguridad: huecos del stock

| Opcion | Stock | Nota |
|---|---|---|
| `ARM64_PTR_AUTH` | off | sin Pointer Authentication (PAC): hardening tipico de Android 14+ ausente |
| `STACK_MPROTECTOR` | off | sin shadow stack |
| `VULNERABILITIES_SPEC_MITIGATIONS` | off | sin mitigaciones automaticas del compilador |
| `KEXEC` / `CRASH_DUMP` | off | no hay kexec ni volcado de crash de usuario |
| `PSTORE_DEFLATE` | off | `PSTORE_RAM` existe, pero sin comprimir |
| `MODULE_SIG_ALL` | on | **los modulos van firmados**: nuestro kernel propio tendra que firmar o desactivar esta opcion para cargar los drivers portados |

## 8. Acciones hechas en el telefono (reversibles, sin flashear)

1. `resetprop ro.vendor.mtk_log_hide_gps 0` -> los logs de GPS dejan de estar
   ocultos (clave para diagnosticar el punto 2).
2. `stop vendor.gnss-default; start vendor.gnss-default` -> reinicio del
   daemon GNSS con los logs visibles.

Para revertir: `resetprop ro.vendor.mtk_log_hide_gps 1`.

## 9. Prioridad de arreglo

1. **GPS** (bloquea un subsistema entero): driver consys 6.6 + lectura de los
   logs de MNLD con una peticion real de fix.
2. **Carga**: exponer `charge_control_limits_*` (arreglo de una tarde).
3. **Droidspaces**: `PID_NS`/`IPC_NS`/`USER_NS`/`SYSVIPC`/`POSIX_MQUEUE` +
   `CGROUP_PIDS` + `FAIR_SCHED`/`CFS_BANDWIDTH` si el kABI lo permite.
4. **Rendimiento**: `LTO_THIN`, `KSM`, `UNIVERSAL_SCALING`/`ENERGY_PERF_BIAS`,
   `NET_CLS_CGROUP`, `PSTORE_DEFLATE`.
5. **Estabilidad**: vigilar `ahb_apb_timeout` y `No free SwRfb` en el kernel
   propio y ver si el manejo de timeouts del SCP mejora.
