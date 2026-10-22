# Touch de ruby (m16): Focaltech FT3680 sobre SPI

## Lo que hay en el telefono (verificado)

- DTB vivo (`/root/ruby-gki/extracted/dts/mt6877.dts`): nodo plataforma
  ```
  touch: touch { compatible = "goodix,touch"; phandle = <0x1b0>; };
  ```
- Overlay de ruby (`ruby-dtbo.dts`, fragmento 25) con el panel de touch:
  ```
  m16-touch@0 {
      compatible = "focaltech,3680-spi", "goodix,9916r-spi";
      reg = <0x0>;                       # SPI
      interrupts = <14 0x2008>;          # GPIO14, edge falling
      spi-max-frequency = <5000000>;     # 5 MHz
      iovdd-supply = <&mt_pmic_vmc_ldo_reg>;
      avdd-supply  = <&mt_pmic_vtp_ldo_reg>;
      panel-id-gpios = <...>;            # selecciona el panel
      focaltech,* / goodix,*  (calibracion y firmware)
  };
  ```
- `dmesg` del kernel stock: `[FTS_TS]fts_change_fps:panel change fps to 120`
  -> el driver activo es **Focaltech**, no Goodix (las props `goodix,*` del
  nodo son la "2nd supply" heredada).

Conclusion: el touch real es **Focaltech FT3680 conectado por SPI3**
(GPIO160 MO, 161 MI, 162 CSB, 163 CLK), con IRQ en GPIO14 y reset en GPIO15.

## Fuentes disponibles

| Origen | Ruta | Que aporta |
|---|---|---|
| ruby 4.19 | `sources/ruby-4.19/drivers/input/touchscreen/focaltech_3680/` | driver del chip FT3680, `focaltech_spi.c` (441 lineas), compatible `focaltech,3680-spi` |
| A34 6.6 | `sources/a34x/kernel/kernel_device_modules-6.6/drivers/input/touchscreen/focaltech_touch/` | capa 6.6 nativa: `mtk_tpd.c` (platform "mediatek,touch"/"goodix,touch"), I2C, gesture, ESD, flash |

Los dos son el mismo linaje de MTK. El de ruby es mas grande
(`focaltech_core.c` 3308 vs 1500 lineas) e incluye el transporte SPI; el de
A34 esta actualizado a 6.6 y trae la capa de plataforma MTK que ruby 4.19
no tiene (aun asi ruby 4.19 la trae como `mediatek/GT9XX_LM` y `gslX680`).

## Nota importante

El A34 **no** soporta el chip FT3680: sus chip ids son FT8xxx/FT5xxx
(`focaltech_config.h`, `FTS_CHIP_TYPE_MAPPING`). A34 solo tiene `NT36532`
(otro fabricante). Por tanto `focaltech_touch` del A34 por si solo no
servira: aunque haga bind al nodo `touch`/`goodix,touch`, no sabra
hablar con el FT3680.

## Plan de port

Opcion A (recomendada): **adaptar el driver de A34 a 6.6 con el SPI y el
chip FT3680 de ruby**.

1. Copiar `focaltech_touch/` a `port/touch/focaltech_touch/`.
2. Anadir el transporte SPI desde `focaltech_spi.c` de ruby 4.19:
   `spi_register_device_info`/`fts_spi_probe`, lectura/escritura por
   `spi_write_then_read`.
3. Anadir el chip id FT3680 al mapa `FTS_CHIP_TYPE_MAPPING` y el
   `compatible = "focaltech,3680-spi"` a la tabla `of_match`.
4. Reutilizar `mtk_tpd.c` de A34: ya declara `{ .compatible = "goodix,touch" }`,
   que es exactamente el nodo plataforma del telefono.
5. Config: `CONFIG_TOUCHSCREEN_FOCALTECH_TOUCH=m` (ya viene en el
   defconfig del A34) + `CONFIG_TOUCHSCREEN_MTK_TOUCH` con la lista de chips.

Opcion B: portar el dir `focaltech_3680/` de ruby 4.19 tal cual a 6.6
(adaptando APIs: `gpio_get_value` -> `gpiod_get_value`, `msleep`/`usleep_range`,
`device_tree` v4.19 -> v6.6, `class_create` con `device_create_data`).
Mas trabajo, pero el driver ya esta escrito para este chip.

## DTS

El nodo `m16-touch@0` vive en el **dtbo** de ruby, no en el DTB base. Al
parchear el DTB hay que anadirlo a mano (mismo contenido que el fragmento 25
del dtbo), con sus overlapped props (el chip real se decide leyendo
`panel-id-gpios`).

## Criterio de aceptacion

```
su -c 'ls /sys/class/input'      # aparece eventX del touch
su -c 'getevent -lt'             # toques con multitouch (ABS_MT_SLOT)
dmesg | grep -i fts              # "FTS_TS" sin errores
```
