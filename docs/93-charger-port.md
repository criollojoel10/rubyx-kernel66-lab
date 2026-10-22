# 93 — Puerto de carga de ruby: inventario y plan

## Lo que monta ruby (overlay `ruby-dtbo.dts`, fragmento 50)

| Dispositivo | Nodo | Direccion |
|---|---|---|
| mp2762 (Xiaomi/MPS) | `mp2762@5c` | I2C 0x5c |
| bq25980 x3 (TI) | `bq25980_standalone1@65`, `2@67`, `3@66` | I2C 0x65/0x67/0x66 |
| sc8551 x2 (Southchip) | `sc8551_i2c7@66`, `sc8551_i2c11@66` | I2C 0x66 |
| sc8561 (Southchip) | `sc8561_master@64`, `sc8561_slave@65` | I2C 0x64/0x65 |
| ln8410 (ADI) | `ln8410_master@66`, `ln8410_slave@67` | I2C 0x66/0x67 |
| max77932 (Maxim) | `max77932@68` | I2C 0x68 |
| xmusb350 (Xiaomi) | `xmusb350@35` | I2C 0x35 (USB-PD / Type-C) |
| bq28z610 (TI, gauge) | `bq28z610@55` | I2C 0x55 |

## De donde sale el codigo

Todo esta en el arbol **4.19 de ruby** (`sources/ruby-4.19`), en rutas
estandar del kernel de Linux (upstream lasBring up-tras el kernel de MTK):

```
drivers/power/supply/mps/mp2762.c
drivers/power/supply/ln/ln8410.c
drivers/power/supply/ti/bq25980.c
drivers/power/supply/southchip/sc8561.c
drivers/power/supply/maxim/max77932.c
drivers/power/supply/xiaomi/xmusb350.c        (+ pd_cp_manager, qc_cp_manager)
drivers/power/supply/mediatek/charger/        (framework MTK: mtk_charger,
                                                mtk_pe*, mtk_dual_switch_charging,
                                                mtk_pdc, step_jeita_charge)
```

El arbol **MTK 6.6 publico de MT6877 no tiene ninguno de estos chips**
(verificado): no son codigo upstream ni de MTK generico, son de Xiaomi/MTK-OEM.

## Lo que ya existe en la base 6.6 (A34/MTK mt6877)

En `drivers/power/supply/` ya esta el framework MTK 6.6:

```
charger_class.c/h        adapter_class.c/h
mtk_charger.c/h          mtk_basic_charger.c
mtk_2p_charger.c         mtk_charger_algorithm_class.c/h
mtk_charger_intf.c       mtk_pd.c/h mtk_pd_adapter.c mtk_pd_hal.c
mtk_pe2.c mtk_pe4.c mtk_pe4_5.c mtk_pe5.c mtk_pe5p.c (+ _hal)
sc8551-charger.c         rt9465.c rt9490-charger.c rt9758-charger.c
ufcs/                    mtk_ufcs_adapter.c
```

Falta (respecto al 4.19 de ruby):

- `mtk_dual_switch_charging.c` (carga de dos canales: el A34 no lo trae)
- `mtk_pdc.c` (power delivery controller)
- `step_jeita_charge.c` (algoritmo Jeita)
- los 7 drivers de chip + `xmusb350` y el gauge `bq28z610`

## Plan

1. **Framework**: portar `mtk_dual_switch_charging.c`, `mtk_pdc.c` y
   `step_jeita_charge.c` del 4.19, comprobando que encajan con
   `mtk_charger_intf.h` de 6.6 (la API de interfaz cambio entre 4.19 y 6.6:
   `mtk_chg_ops`, `charger_class`...).
2. **Chips**: portar los 8 drivers I2C. Son drivers de I2C/regulator
   auto-contenidos: el trabajo es adaptation de API (regulator_bulk,
   `devm_regulator_get`, `i2c probe` con `of_property`, etc.) y de los
   nombres de symbolos que usan del framework MTK.
3. **USB-PD**: `xmusb350.c` + `pd_cp_manager.c`/`qc_cp_manager.c` (Xiaomi),
   que ademas habla con `mtk_pd`/`mtk_ufcs_adapter` de 6.6.
4. **Gauge**: `bq28z610` (TI) para el porcentaje de bateria; hay que ver si
   el vendor de ruby lo usa o si el gauge de MTK (`mt6359p-gauge.c`, ya
   presente) es suficiente.

## Criterio de aceptacion

```
su -c 'ls /sys/class/power_supply'       # battery, mtk_charger, charger.1, usb
su -c 'cat /sys/class/power_supply/battery/capacity'
su -c 'dumpsys battery'                  # status: charging con cargador puesto
```
