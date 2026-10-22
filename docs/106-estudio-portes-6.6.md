# Estudio: portes de MTK 4.19 → 6.6 en otros dispositivos

Complementa a `docs/105-referencias-6.6.md` (Volla frente a A34) y a
`docs/104-gaps-vivos.md` (qué falta). Aquí solo va lo que otros árboles
demuestran.

## 0. No existe un 6.6 público para ruby

Todos los árboles de ruby son 4.19.x:

| Repo | Rama | Versión |
|---|---|---|
| `RubyxLabs/kernel_xiaomi_mt6877` | `lineage-23.2` | 4.19.325 |
| `DXRN-MoonWake/moonwake_kernel_xiaomi_ruby` | `moon` | 4.19.325 |
| `crdroidandroid/android_kernel_xiaomi_mt6877` | `16.0` | 4.19.325 |
| `AxionAOSP-devices/…`, `AlphaDroid-devices/…`, `daria-community/kernel_daria_mt6877` | `lineage-23.2`, `fifteen-qpr2` | 4.19.325 |
| `xiaomi-mediatek-devs/android_kernel_xiaomi_mt6877` | `alps13-4.19-pqe-ruby`, `fifteen`, `lineage-21` | 4.19.191/325/321 |

MT6877 en 6.6:

- `HelloVolla/android_kernel_volla_mt6877` + `…_device_modules_volla_mt6877`,
  rama `volla-16.0` → **6.6.89**, Android 16, arranca en hardware real.
- `Mayuri-Chan/MTK_kernel_device_modules_6.6` (`lineage-22.1`): DM genérico 6.6
  con `sound/soc/mediatek/mt6877` y `tee/teei/{400,510,515}`.
- `MotorolaMobilityLLC/kernel-kernel_device_modules-6.6`
  (`android-15-release-…`): mismo layout de tee, sin huella.
- Ojo: `HelloVolla/…_mt6878` es 6.1 y `…_mt6789` es 5.10, no 6.6.

## 1. Tabla de referencias

| Subsistema | Referencia 6.6 | Qué demuestra | ¿Reutilizable? |
|---|---|---|---|
| Panel m16 | `HelloVolla/…device_modules…/drivers/gpu/drm/panel/panel-boe-rm692e5-cmd.c` | plantilla de panel v2: `mtk_panel_ext_create()`, `lcm_get_modes(panel, connector)` | sí, como plantilla |
| Panel m16 (2) | `itswill00/android_kernel_xiaomi_tanzanite` (5.10) `drivers/gpu/drm/panel/panel-n6-42-0d-0a-dsc-vdo.c` | mismo `mtk_ddic_dsi_send_cmd()` y `mtk_panel_funcs` que nuestro port | sí, para diff |
| Táctil FT3680 | `…/drivers/input/touchscreen/focaltech_touch/` | es **solo I2C** (`focaltech_i2c.o`, sin `focaltech_spi.c`) y sin FT3680 | **no** |
| Huella | `NothingOSS/android_kernel_device_modules_6.1_nothing_mt6878` `drivers/input/fingerprint/goodix/gf_spi_tee.c` | driver Goodix moderno (2.133 líneas) | sí, pero es 6.1-clean |
| Audio | `HelloVolla/…/sound/soc/mediatek/mt6877/mt6877-mt6359.c` (1.531 líneas) | dai_links propios para el amplificador externo | sí, con matices |
| TEE | `HelloVolla/…/drivers/tee/teei/` (`400/`, `510/`, `515`→symlink a 510) | Kconfig por defecto `"400"` y el overlay de MT6877 no cambia la versión | **sí: 400** |
| geniezone / trusted_mem | `kernel_device_modules-6.6/drivers/misc/mediatek/{geniezone,trusted_mem}` del A34 | 6.6 añade `gz_ffa`, `tz_system`, `ffa_v11/`, `mtee_devices` | ya está en el A34 |
| GPS | `sources/a34x/vendor/mediatek/kernel_modules/connectivity/gps/*` | el stack pasó de `drivers/misc` a `vendor/…/connectivity/gps` con `BUILD.bazel` | ya está, solo se mueve |
| Carga | Volla usa `SC8551 + CW2217` | otra topología de carga | **no** para mt6360 |

## 2. Por subsistema

### TEE: el dato más importante

Los dos árboles independientes de MT6877 en 6.6 convergen en **TEEI 400**:

- Ruby 4.19 (`sources/ruby-4.19/drivers/tee/teei/`) solo tiene `400/`.
- Volla 6.6.89: `drivers/tee/teei/{400,510,515}` con `515` como symlink a
  `510`, `Makefile` construye `$(CONFIG_MICROTRUST_TEE_VERSION)/` y el Kconfig
  deja el valor por defecto en `"400"`; su `mt6877_overlay.config` **no**
  define `MICROTRUST_TEE_VERSION`.
- A34 6.6: Kconfig por defecto `"510"`, pero
  `kernel/configs/mt6877_teegris_5_overlay.config` fija
  `MICROTRUST_TEE_SUPPORT=y` + `MICROTRUST_TEE_VERSION="400"`.

Conclusión: la firma está en el firmware de la partición `tee`, que es 400;
510/515 exigirían blobs ISEE que ruby no tiene. Nuestro port ya va por 400.

### Audio: el detalle que rompe el altavoz

Volla nombra los enlaces `COMP_CODEC("aw883xx_smartpa_0", "aw883xx-aif-0")`,
mientras ruby 4.19 usa enlaces privados `aw882xx_smartpa.7-0034` /
`.7-0035` (más `MTK_SPK_AW_AW882XX_STR`). Es decir: **no solo cambia
aw882xx→aw883xx, cambia el patrón de nombre**
(`<driver>_smartpa.N-ADDR` frente a `<driver>_smartpa_0`). Esa es la trampa
real al reutilizar el código de Volla; nuestro `awinic_codecs[]` ya usa el
patrón de ruby.

### Huella

`gf_spi_tee.c` del árbol de Nothing sigue usando `class_create(THIS_MODULE, …)`
(línea 1868) y `of_get_named_gpio(... "fpid-gpio")` (1741), o sea que es
6.1-clean, no 6.6-clean. Nuestro `port/fingerprint/goodix_cap/gf_spi_tee.c`
tiene la TA correcta (`uuid_ta_gf = {0x8888c03f,…}`, línea 113) y también
`class_create(THIS_MODULE, …)` en la 2341: **hay que pasarlo a un argumento**.

### Display

No hay ningún port de panel m16 a la API v2 en ningún repo público
(`search/code` de `panel-m16` en Volla → 0 resultados; `42-0d-0a` solo aparece
en 4.19 y en DTSI de Qualcomm). Nuestro `port/display/` es el único. La
plantilla v2 de Volla y el `panel-n6-42-0d-0a` de tanzanite (5.10) sirven para
contrastar.

### Táctil

El `focaltech_touch` de Volla es I2C y selecciona `_FT8201`/`_FT3528`: no vale
para el FT3680 por SPI3 de ruby. El camino sigue siendo nuestro
`port/touch/focaltech_3680/` (con `focaltech_spi_v2.c`).

### geniezone y trusted_mem

El 6.6 del A34 añade `gz_ffa.c`, `gz_ffa.h`, `tz_system.c` a la base de 4.19,
y en `trusted_mem/` añade `ffa_v11/`, `mtee_impl/`, `mtee_devices.c`,
`peer_mgr.c`, `profiler.c`. Volla no los usa (va por KREE/FFA, gateado por
`CONFIG_MTK_GZ_KREE`/`CONFIG_MTK_PKVM_TMEM`). Nosotros nos quedamos con los del
A34, que es la vía que ya compila.

## 3. Trampas de API 4.19 → 6.6, verificadas en el árbol local

- **`class_create()` tiene un solo argumento** en este 6.6:
  `include/linux/device/class.h:236` → `struct class * __must_check
  class_create(const char *name);`. Todo `class_create(THIS_MODULE, …)` es
  error de compilación.
- **`remove_new`**: `include/linux/platform_device.h:253-254` tiene `int
  (*remove)` y `void (*remove_new)`, pero `struct spi_driver` **no** tiene
  `remove_new` en este árbol. Para SPI se mantiene `int (*remove)`; para
  `platform_driver` sí se puede usar `remove_new`.
- **`of_get_named_gpio()` sigue existiendo** (`include/linux/of_gpio.h:22`):
  migrar a `devm_gpiod_get()` es recomendable, no obligatorio.
- El HAL `mtk_spi` desapareció para el FT3680, pero el driver usa el SPI
  genérico, así que no hay que reescribir la capa de bus.

## 4. Sin verificar (no inventar rutas)

- Si `mtk_ddic_dsi_send_cmd()` existe todavía en 6.6 (nuestro README dice que
  no; solo se confirmó su uso en el 5.10 de tanzanite).
- Deltas de `struct snd_soc_dai_link` (`cpus/codecs/platforms` frente a
  `.cpu_dai_name`).
- Rutas de mt6360 en el GKI (el A34 lo trae como device module).
- Diferencia de API entre `isp6s` e `isp6s_mon` (ver `docs/107-camara-isp6s.md`).

## 5. Qué copiar, en orden

1. **TEEI 400** — ya alineado; confirmar con `mt6877_teegris_5_overlay.config`
   que el símbolo de versión es `"400"` (hecho).
2. **Panel n6 ↔ m16** — diff de `panel-n6-42-0d-0a` (5.10) contra nuestro
   `panel-m16-42-0d-0a` para cazar llamadas v2 que falten.
3. **Goodix 6.1 → 6.6** — `class_create` a un argumento en
   `port/fingerprint/goodix_cap/gf_spi_tee.c:2341`.
4. **Audio** — revisar el patrón de nombre de los dai_links antes de tocar
   nada más.
5. **GPS** — no hay nada que portar; solo el movimiento de directorio y el
   `.rc` del ramdisk.
