# 13 — Fase 5: arquitectura del primer kernel ruby

## Hechos medidos

| Dato | Ruby stock | A34 6.6.127 |
|---|---|---|
| Modelo | GKI + drivers MTK **built-in** | GKI + **978 módulos** |
| Módulos en vendor | 78 genéricos, 0 MTK | 978 `.ko` (incluye tests) |
| `vendor_boot` | no existe | no existe |
| Partición boot | 128 MB, header v2 con DTB | 64 MB, header v4 sin DTB |

El build de referencia del A34 produjo 978 `.ko`. Ruby solo tiene 78 módulos
GKI y todos los drivers MTK dentro del `Image`.

## Opciones

### A. Built-in mínimo (recomendada para el primer arranque)

Copiar al árbol `kernel-6.6` los drivers MTK imprescindibles y compilarlos
`=y`:

- `clk-mt6877*`
- `pinctrl-mt6877`
- PMIC MT6359 / RTC
- MMC/UFS MediaTek
- IOMMU, watchdog
- UART 8250 MT6577

Ventajas:

- no depende de cargar módulos antes de tener storage/vendor;
- coincide con la arquitectura del kernel stock de ruby;
- permite un `Image` + DTB + ramdisk en `boot.img` (header v2), sin
  `vendor_boot`.

Riesgos:

- los drivers de `kernel_device_modules-6.6` usan headers MTK downstream que
  no están en `kernel-6.6`;
- hay que resolver dependencias de clk/pinctrl/PMIC;
- el `Image` crece (el stock ronda 53 MB raw).

### B. GKI + módulos (fiel al A34)

Mantener el `Image` GKI y empaquetar un subconjunto curado de `.ko` en el
ramdisk o en `vendor/lib/modules`, con un init que los cargue.

Ventajas:

- reutiliza el Image y los módulos ya compilados del A34;
- no mezcla código downstream en el GKI.

Riesgos:

- ruby no tiene `vendor_boot`; habría que meter los módulos en el ramdisk de
  `boot.img` (128 MB) o modificar `vendor.img`;
- orden de carga y dependencias (`modules.dep`) antes de storage;
- el A34 tiene 978 módulos; hay que elegir un subconjunto y probar.

## Decisión

Para el primer hito de consola **A**, con un piloto acotado:

1. clk + pinctrl MT6877 built-in;
2. PMIC/RTC MT6359 con alias `mt6359-*`;
3. UART 8250 MT6577;
4. MMC/UFS;
5. watchdog/IOMMU.

Si el piloto no compila por headers downstream, se evalúa B con un ramdisk de
módulos.

## Piloto de la Fase 5

Antes de tocar el árbol completo:

```
port/
├── clk/
│   ├── clk-mt6877.c
│   └── clk-mt6877-*.c
├── pinctrl/
│   └── pinctrl-mt6877.c
└── README.md
```

Cada archivo se copia de
`sources/a34x/kernel/kernel_device_modules-6.6` y se compila contra
`sources/a34x/kernel-6.6` para medir:

- headers MTK ausentes;
- APIs de clk/pinctrl cambiadas;
- símbolos exportados que falten.

Criterio de salida: un `Image` 6.6.127 con clk/pinctrl MT6877 built-in y el
DTS mínimo, sin módulos MTK externos.

## Droidspaces

Las opciones `PID_NS`, `IPC_NS`, `SYSVIPC`, `POSIX_MQUEUE` van en el defconfig
del **GKI core**, no en los módulos. Deben entrar en este mismo build para no
repetir el trabajo de kABI después.
