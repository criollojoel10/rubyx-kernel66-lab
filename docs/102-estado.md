# 102 — Estado del kernel 6.6 de ruby (2026-10-22)

## Resumen

| Subsistema | Estado | Detalle |
|---|---|---|
| Base del kernel | **OK** | GKI de MTK 6.6.127 (A34) + device modules de MTK para MT6877 |
| Device Tree | **OK** | El DTB 6.6 de ruby ya esta extraido; el dtbo aporta `panel2@0` = `m16_36_02_0b_dsc_vdo,lcm` y `m16-touch@0` = `focaltech,3680-spi` |
| Display | **listo** | El panel m16 36-02-0b esta portado a 6.6 en `port/display/` (copiado al GKI). El hardware es el mismo que en el A34: mismo SoC MT6877 |
| Tactil | **listo** | El driver del FT3680 por SPI esta portado en `port/touch/` (copiado al GKI). Es el chip que monta ruby |
| TEE (keymaster/FBE) | **en build** | Microtrust TEEI 400 de los device modules, compilado built-in como en ruby |
| Carga | **en build** | mp2762, ln8410, bq25980, sc8561, max77932, xmusb350 portados del 4.19 de ruby |
| GNSS / GPU / camara | **fuente localizada** | `vendor/mediatek/kernel_modules` publico de MTK 6.6 para MT6877 (gps_stp, mali, mtkcam) |
| Droidspaces | **en build** | Parche kABI oficial + config GKI (workflow dedicated) |
| Flash de prueba | **OK** | `scripts/test-ruby-kernel.sh <run>`: artefacto -> boot.img -> slot B (tries=1) -> verificacion |

## El cambio de fondo de esta sesion

El A34 5G es un **MT6877** (Exynos 1380) y ruby monta **el mismo panel m16 36-02-0b** y
**el mismo tactil Focaltech FT3680** que ruby. Samsung ya los portó a 6.6, asi
que **display y tactil no hay que portarlos**: se activan en el config.

Lo que si faltaba era el **TEE** (ruby usa Microtrust TEEI 400, el A34 usa
TEEGRIS de Samsung) y los **cargadores** de Xiaomi.

## Como se compila cada cosa (resumen)

- El GKI se compila con el `.config` de los device modules.
- Los device modules solo se compilan si el GKI los incluye en su
  `Makefile.ext` (`obj-y += ../kernel/kernel_device_modules-6.6/drivers/tee/`).
- Los `.ko` que Kleaf recoge son los de `mgk_64_device_modules`; declarar uno
  ahi hace que el build **falle si no se produce** (un build verde significa que
  el modulo existe).

Detalle completo en `docs/101-arquitectura-build-mtk.md`.

## Comandos

```sh
# build (CI)
gh workflow run -R criollojoel10/rubyx-kernel66-lab build-ruby-full.yml --ref main
gh workflow run -R criollojoel10/rubyx-kernel66-lab build-ruby-full-droidspaces.yml --ref main

# probar en el telefono (auto-retorno al slot A)
scripts/test-ruby-kernel.sh <run-id>
```

## Lo que falta para el cierre

1. Build verde del kernel completo (display + tactil + TEE + carga).
2. Montar la imagen y arrancar en el slot B: comprobar imagen, tactil, TEE
   (`/dev/ut_keymaster`), `init_user0` sin fallo y `droidspaces check`.
3. Carga real con cargador enchufado.
4. GPS con fix (modulos vendor de MTK).
5. Dejar el kernel en el slot A de forma permanente.

## Pendiente: huella (goodix por SPI)

El dtbo de ruby define el nodo de la huella como un dispositivo SPI con
`compatible = "goodix,goodix-fp"` (`netlink-event = <0x1e>`,
`vfp-supply = <&mt_pmic_vfp_ldo_reg>`).

En el A34 (MT6877, 6.6) **no hay driver de huella goodix**: solo el del
tactil (`drivers/input/touchscreen/goodix`). El de la huella en MTK 6.6
vive en `vendor/mediatek/kernel_modules/mtk_input/fingerprint/goodix/6.6`,
ruta que no esta en el repo publico de modulos vendor.

Opciones: (a) portar `drivers/input/fingerprint/goodix_cap` del 4.19 de ruby
(como se hizo con el tactil), (b) buscar el arbol de modulos vendor que lo
incluya. No bloquea el arranque ni ninguna otra funcion.
