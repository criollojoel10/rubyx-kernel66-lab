# Piloto clk/pinctrl MT6877

Copias de solo lectura del árbol del A34 para medir el port built-in.

Origen:

```
UN1CA/kernel_samsung_a34x
tag 6.6.127_2026-04-06_A346BXXSEEZB6
kernel/kernel_device_modules-6.6/drivers/{clk,pinctrl}/mediatek
```

## Auditoría

`make audit-pilot` (`scripts/audit-pilot.py`) sobre 19 archivos:

| Header compartido | Líneas de diferencia GKI vs device modules |
|---|---:|
| `clk-mtk.h` | 305 |
| `clk-gate.h` | 70 |
| `clk-mux.h` | 484 |
| `pinctrl-paris.h` | 22 |

Los includes resuelven, pero el clk del device modules usa una versión
**extendida** del framework (hardware voter, mmdvfs, clkchk, dramc), no la del
GKI. Copiar `clk-mt6877.c` sin más no compila.

`pinctrl-mt6877.c` (788 líneas) solo necesita los macros de
`pinctrl-paris.h` (22 líneas de diferencia). Es el piloto de menor riesgo.

## Orden

1. **Pinctrl** built-in en `kernel-6.6` (piloto).
2. Clk se queda como módulo del A34 por ahora.
3. Si pinctrl compila y arranca, evaluar el port del framework clk.

## Licencia

GPL-2.0, heredada de los archivos originales.
