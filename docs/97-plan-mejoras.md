# 97 — Que arreglar y mejorar en el kernel propio

Lista de trabajo ordenada por impacto, extrait del analisis del kernel stock
(`docs/95`, `docs/96`) y de la config real del telefono.

## A. Funcionalidad que falta o esta rota

| # | Que | Situacion en el stock | Como lo arreglamos |
|---|---|---|---|
| A1 | **Droidspaces** | faltan `PID_NS`, `IPC_NS`, `USER_NS`, `SYSVIPC`, `POSIX_MQUEUE`, `CGROUP_PIDS`, `CHECKPOINT_RESTORE`; ademas `FAIR_SCHED`/`CFS_BANDWIDTH` **off**, asi que los limites de CPU por cgroup no funcionan | parche kABI oficial + fragment propio; medir el impacto en el kABI con `scripts/check-kabi.py` y regenerar la baseline |
| A2 | **GPS** | el chip arranca pero la sesion se aborta a los 35 s; el bus conninfra esta en timeout permanente (1 Hz) | portar el driver GDL de MTK 6.6; probar con WiFi off para aislar el reparto de conninfra |
| A3 | **Carga** | `Max charging current/voltage = 0`; no hay `charge_control_limits_*` en ningun nodo de `power_supply` | en el puerto de carga 4.19->6.6, exponer los limites y el estado de los canales master/slave |
| A4 | **Conectividad** | 211 `ahb_apb_timeout` continuos, 150 `No free SwRfb`, WLAN con 78 s de CPU en sondeos | vigilar en el kernel propio; revisar power/clock de conninfra |

## B. Rendimiento

| # | Que | Stock | Propuesta |
|---|---|---|---|
| B1 | **Memoria** | 1,1 GB en ZRAM, 356 000 paginas compactadas, 6 M de `workingset_refault_file`, 2,4 M de `pgmajfault`, 1,98 M de `pgscan_direct`, 3,5 GB de swap usada | revisar `vm.swappiness` (100), `vm.page-cluster` (0), `vm.watermark_scale_factor`, tamano de ZRAM y `KReclaimable` (411 MB de slab) |
| B2 | `LTO_CLANG` / `LTO_THIN` | off | activar LTO thin si el kABI lo aguanta (afecta a los CRC: hay que rehacer la baseline) |
| B3 | `KSM` | off | activar: deduplica paginas entre apps y reduce presion de memoria |
| B4 | `UNIVERSAL_SCALING`, `ENERGY_PERF_BIAS` | off | son los mandos del EAS/uclamp de MTK: sin ellos se pierde afinidad de CPU y politica termica fina |
| B5 | `NET_CLS_CGROUP` | off | permite marcar trafico por cgroup (mal impacting) |
| B6 | `NO_HZ_FULL` | off | evaluarlo: full dynticks reduce latencia de salida de idle, pero en movil puede hacer subir el consumo |
| B7 | `PSI` / `LRU_GEN` / `ZRAM` / `HZ_250` | on | se dejan como estan |
| B8 | `PSTORE_DEFLATE` | off | activarlo: los volcados de pstore ocuparan mucho menos |

## C. Seguridad

| # | Que | Stock | Nota |
|---|---|---|---|
| C1 | `ARM64_PTR_AUTH` | off | Pointer Authentication: hardening tipico de Android 14+ |
| C2 | `STACK_MPROTECTOR` | off | shadow stack |
| C3 | `VULNERABILITIES_SPEC_MITIGATIONS` | off | mitigaciones automaticas del compilador |
| C4 | `MODULE_SIG_ALL` | **on** | nuestros modulos portados tendran que ir firmados o hay que desactivar la opcion |
| C5 | `KEXEC` / `CRASH_DUMP` | off | no hay kexec ni volcado de crash |
| C6 | `PSTORE_RAM` | on | bien: dejalo, y con `PSTORE_DEFLATE` (B8) |

## D. Arranque y estabilidad

- D1: medir el tiempo de arranque y compararlo con el stock (`dumpsys` /
  `bootstat`).
- D2: vigilar `pstore` por si hay crashes del kernel en el uso diario
  (`scripts/read-pstore.sh` ya existe).
- D3: el log del kernel esta lleno de ruido de WLAN (`halDumpMsduReportStats`
  cada 20 s, `ccci1/dpmf` cada 10 s). En el kernel propio conviene bajar el
  nivel de log de esos drivers para no gastar CPU en printing.

## E. Lo que ya esta bien (no tocar)

Display 120 Hz con HDR, camaras, UFS, EROFS/F2FS, WiFi/BT, termica, CFI,
shadow stack, randomize base, fortify, stackprotector strong, MGLRU, PSI,
ZRAM, `sys.boot_completed`, SELinux (0 avc denied en el stock).
