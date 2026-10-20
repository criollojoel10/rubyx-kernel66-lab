# 17 — Cierre de dependencias de módulos

## Problema

Los 43 módulos seleccionados no son autocontenidos. `modinfo` mostró:

```
clk-mt6877*        -> clk-common
clk-mt6877-pg      -> clkchk-mt6877, clk-common
mt6359p_battery    -> aee_aed, pmic_lbat_service
iommu_gz           -> gz_tz_system
```

Si se meten esos 43 en el ramdisk, `insmod` fallará en el primer módulo que
dependa de `clk-common`.

## Solución

1. El colector ahora guarda **los 978 `.ko`** en
   `a34-all-modules.tar.zst` (el bundle de 43 sigue existiendo).
2. `scripts/close-module-deps.py` recorre `modinfo -F depends` desde la lista
   raíz y calcula el cierre transitivo.
3. Los nombres que no estén entre los 978 se reportan como
   `missing_from_set`; si son drivers GKI built-in, no hace falta empaquetarlos.

Salida:

```
port/modules/boot-modules-closure.list
port/modules/closure.json
```

## Validación

- Todos los `.ko` del cierre deben compartir el mismo `vermagic`.
- `modules.dep` se puede regenerar con `depmod` sobre el directorio extraído.
- No se declara “listo para arrancar” hasta que el cierre no tenga faltantes
  que no sean built-in.

## Siguiente

Con el cierre calculado:

1. copiar solo esos `.ko` al ramdisk;
2. generar `modules.dep`, `modules.alias`, `modules.load`;
3. reempaquetar el ramdisk stock de ruby;
4. validar el `boot.img` con `unpack_bootimg` antes de flashear.
