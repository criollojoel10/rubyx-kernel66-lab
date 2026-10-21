# 27 — El dtbo de la ROM y el DTB correcto

## Qué contiene el dtbo

`dtbo.img` de la release `rubyx-20261015`:

```
magic        d7b7ab1e
entries      1 (RUBY)
dt_size      76 799 B
```

Es un **overlay plugin** (`/plugin/;`) con `model = "RUBY"` y **62 targets**:

```
&odm, &pio, &mtkfb, &dispsys_config, &dsi0, &dsi_te,
&i2c0..&i2c11, &spi1/3/5, &goodix_fp, &touch, &touch_panel,
&mmc0/1, &mt6360_pmic, &mt6360_typec, &ruby_charger,
&ruby_pd_cp_manager, &bat_gm30, &gps, &consys, &sound...
```

Ahí viven los nodos de:

- paneles `m16_42_0d_0a`, `m16_36_02_0b`, `m16_45_02_0c`;
- touch `focaltech,3680-spi` / `goodix,9916r-spi`;
- fingerprint `goodix,goodix-fp`;
- backlight, LEDs, vibrator;
- cargadores ruby/rubyplus/rubypro;
- cámaras, NFC, GPS, etc.

## Hallazgo crítico

| DTB | `__symbols__` | Targets dtbo presentes |
|---|---:|---:|
| stock ruby + probe | 445 | **62/62** |
| `dts/ruby-minimal.dtb` (base A34) | **0** | **0/62** |

El DTB generado desde el `mt6877.dts` del A34 **no tiene `__symbols__`**, así
que el bootloader no puede aplicar el dtbo. Eso explica que el test 5
arrancara pero sin display/touch: el overlay se ignoraba.

## Decisión

El DTB base definitivo **no** puede ser el del A34. Debe ser el **DTB stock de
ruby**, que conserva los símbolos que el dtbo necesita.

Se creó:

```
scripts/make-stock-dtb.py
dts/ruby-stock-base.dtb   179 275 B
dts/ruby-stock-base.dts   216 KiB
```

El script:

1. extrae el DTB del `boot_b` stock;
2. añade `pstore@48090000` y `ruby-dtb-probe`;
3. conserva `__symbols__`;
4. valida los 62 targets del dtbo.

Resultado:

```
symbols=445  dtbo_targets=62  missing=0
```

## Cómo proceder

1. Usar `dts/ruby-stock-base.dtb` como base para la siguiente imagen.
2. Mantener el dtbo de la ROM tal cual; no duplicar panel/touch/charger en el
   DTB propio.
3. El kernel sigue necesitando los drivers (pantalla, touch, carga); el dtbo
   solo describe el hardware.
4. `dts/ruby-minimal.dtb` del A34 queda como experimento de SoC, **no** para
   Android.

## Estado

No se ha flasheado nada nuevo. El dispositivo está en Android A con
`boot_b`/`misc` stock.
