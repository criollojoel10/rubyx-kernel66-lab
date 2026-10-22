# Carga de ruby: lo que hay que portar del A34 6.6

## Lo que usa el telefono (overlay `ruby-dtbo.dts`, fragmento 50)

| Dispositivo | Nodo | Direccion |
|---|---|---|
| mp2762 | `mp2762@5c` | I2C 0x5c |
| bq25980 (1) | `bq25980_standalone1@65` | I2C 0x65 |
| bq25980 (2) | `bq25980_standalone2@67` | I2C 0x67 |
| bq25980 (3) | `bq25980_standalone3@66` | I2C 0x66 |
| bq25980 (4) | `bq25980_standalone4@68`? | (revisar) |
| sc8551 (i2c7) | `sc8551_i2c7@66` | I2C 0x66 |
| sc8551 (i2c11) | `sc8551_i2c11@66` | I2C 0x66 |
| sc8561 master | `sc8561_master@64` | I2C 0x64 |
| sc8561 slave | `sc8561_slave@65` | I2C 0x65 |
| ln8410 master | `ln8410_master@66` | I2C 0x66 |
| ln8410 slave | `ln8410_slave@67` | I2C 0x67 |
| bq28z610 | `bq28z610@55` | I2C 0x55 (fuel gauge) |
| max77932 | `max77932@68` | I2C 0x68 (PD/charger) |
| xmusb350 | `xmusb350@35` | I2C 0x35 (USB-PD / Type-C) |

## Estado en A34 6.6

Infraestructura MTK de carga: **si existe** (`drivers/power/supply/`):

- `mtk_basic_charger.c`, `mtk_2p_charger.c`, `mtk_charger_algorithm_class.c`
- `mtk_battery.c`, `mtk_battery_algo.c`, `mtk-battery-manager.c`
- `charger_class.c`, `adapter_class.c`
- `mt6359p-gauge.c` (gauge del PMIC de ruby), `mt6375-gauge.c`

Drivers de carga especificos: **no existen** en A34 6.6

```
mp2762  bq25980  sc8551  sc8561  ln8410  bq28z610  max77932  xmusb350
```

Ninguno aparece en el arbol del A34 (`find drivers -iname '*<chip>*'` vacio).

## Implicacion

La carga de ruby depende de una cadena de drivers que hay que portar del
arbol 4.19 de ruby (o de otras fuentes MTK 6.6) **y** de que el kernel
6.6 hable el mismo ABI con los drivers de charging de Android
(`healthd`/`charger` de `vendor`).

Cosa buena: `mtk_charger` de 6.6 es el mismo framework que usa el A34, y
`mt6359p-gauge.c` ya esta. Si el vendor de ruby usa la interfaz `mtk_charger`
(MTK 5.4 -> 6.6), el HAL deberia funcionar con los drivers 6.6 de los chips.

Orden sugerido:

1. `xmusb350` (USB-PD) - sin el, no hay carga rapida ni reversed port.
2. `mp2762` / `max77932` / `bq25980` - cargadores principales.
3. `sc8551` / `sc8561` / `ln8410` - battery chargers (canal slave/master).
4. `bq28z610` - fuel gauge (porcentaje de bateria).

## Criterio de aceptacion

```
su -c 'ls /sys/class/power_supply'      # battery, mtk_charger, usb
su -c 'cat /sys/class/power_supply/battery/capacity'
su -c 'dumpsys battery'                 # nivel y estado de carga
```
Con el cargador enchufado: `dumpsys battery` debe mostrar
`status: charging` y `level` subiendo.
