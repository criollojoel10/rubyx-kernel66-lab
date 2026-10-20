# 14 — Fase 5: piloto pinctrl/clk

## Objetivo

Medir si los drivers MT6877 del A34 pueden compilarse **built-in** contra el
GKI `kernel-6.6`, antes de intentar el kernel completo.

## Archivos copiados

```
port/clk/       18 archivos clk-mt6877* (incluye clk-mt6877-pg.c de 133 KiB)
port/pinctrl/   pinctrl-mt6877.c (788 líneas) + pinctrl-mtk-mt6877.h
```

Origen fijado en `port/README.md` (tag/commit del A34).

## Auditoría automática

`scripts/audit-pilot.py`:

```
19 archivos
0 includes sin resolver
```

Pero resolver el include no significa que la API sea la correcta. Los headers
compartidos difieren:

| Header | GKI vs device modules |
|---|---:|
| `clk-mtk.h` | 305 líneas |
| `clk-gate.h` | 70 líneas |
| `clk-mux.h` | 484 líneas |
| `pinctrl-paris.h` | 22 líneas |

### Clk

El `clk-mtk.h` del device modules añade hardware voter, `mmdvfs_v3`, `clkchk`,
`dramc` y tipos propios. No es el framework del GKI. Copiar `clk-mt6877.c`
directamente produciría errores de tipos/API.

Conclusión: clk **no** es un piloto barato. Se queda como módulo del A34
mientras se valida el resto.

### Pinctrl

`pinctrl-mt6877.c` solo requiere tres macros añadidos a `pinctrl-paris.h`
(`MTK_PINCTRL_DEV`, `MTK_PIN_NODRV`, `MTK_PIN_EINT`). El parche son 45 líneas.

Conclusión: **pinctrl es el piloto**.

## Aplicación

```sh
./port/pinctrl/apply.sh /ruta/a/kernel-6.6
```

Copia el driver, aplica el parche de `pinctrl-paris.h` y añade la entrada
Kconfig/Makefile (`PINCTRL_MT6877`, `PINCTRL_MTK_PARIS`).

Todavía **no** se ha compilado: falta un build del GKI con
`CONFIG_PINCTRL_MT6877=y` y el DTS mínimo. Ese es el siguiente experimento de
CI.

## Criterio de salida

```
CONFIG_PINCTRL_MT6877=y
pinctrl-mt6877.c compila sin errores
Image 6.6.127 incluye el driver
```

Si falla, el log dirá exactamente qué API de `pinctrl-paris` falta; no se
oculta con parches a ciegas.
