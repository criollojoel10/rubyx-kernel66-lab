# 101 — Arquitectura del build de MTK 6.6 (MGK) y dónde va cada driver

Documento de referencia del laboratorio. Resume como esta construido el
arbol que usamos y, sobre todo, **en que parte del build se compila cada
driver**, que es la clave para no perder horas de CI.

## Los dos arboles

```
sources/a34x/                              (UN1CA/kernel_samsung_a34x)
├── kernel-6.6/                            GKI 6.6.127 (MTK 6.6, base Samsung)
│   ├── drivers/gpu/drm/mediatek/          API de display v1 (mtk_disp_*)
│   ├── drivers/gpu/drm/panel/             paneles v1 + el m16 de ruby (v2)
│   ├── drivers/input/touchscreen/         focaltech_3680 (el tactil de ruby)
│   └── Makefile.ext                       -> aqui se enganchan los device modules
└── kernel/kernel_device_modules-6.6/      device modules de MTK para MT6877
    ├── drivers/tee/teei/{400,510,515}/    Microtrust (TEE) y TEEGRIS
    ├── drivers/gpu/drm/mediatek/mediatek_v2/   API de display v2
    ├── drivers/gpu/drm/panel/             paneles de MTK
    ├── drivers/input/touchscreen/         focaltech_touch (I2C), GT9xx, goodix
    └── drivers/power/supply/              mtk_charger y familia
```

## El A34 ya trae el display y el tactil de ruby

El A34 5G es un **MT6877** (Exynos 1380) con **el mismo panel m16 36-02-0b**
y **el mismo tactil Focaltech FT3680** que ruby. Samsung ya los portó a 6.6:

```
kernel-6.6/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c
    compatible = "m16_36_02_0b_dsc_vdo,lcm"     (el del dtbo de ruby)
kernel-6.6/drivers/input/touchscreen/focaltech_3680/
    compatible = "focaltech,3680-spi"           (el del dtbo de ruby)
    _FT3680 = 0x3680008A
```

**⇒ No hay que portar display ni tactil**: solo activarlos en el config
(`CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO`, `CONFIG_TOUCHSCREEN_FOCALTECH_3680`).

Los ports que.Resolveiamos en el laboratorio (`port/display/`, `port/touch/`)
eran redundantes: el panel m16 de los device modules del A34 es el mismo
fichero, y el driver del tactil es identico al `focaltech_3680` del GKI.

## Como se compila cada cosa (MGK)

El build de MGK compila **un solo kernel** con el `.config` de los device
modules, pero con los ficheros de dos arboles:

1. **El GKI** se compila con sus propios Makefiles (`drivers/...`).
2. **Los device modules** se compilan porque el GKI los incluye en su
   `Makefile.ext`:

   ```make
   obj-y += ../$(DEVICE_MODULES_REL_DIR)/drivers/tee/
   obj-y += ../$(DEVICE_MODULES_REL_DIR)/drivers/gpu/drm/mediatek/
   ```

   (asi lo hace el arbol publico de MTK para MT6877). Con esa inclusion, lo
   que hay en esos directorios se compila **built-in** (=y) dentro del
   kernel, que es exactamente como esta el kernel stock de ruby.

3. Con `CONFIG_DEVICE_MODULES_ALLOW_BUILTIN=n` (el valor por defecto del
   A34) **no se compila nada** de los device modules: por eso el build de
   referencia del A34 no trae ni `isee.ko` ni los drivers de display.

4. Los `.ko` que Kleaf recoge en el target `mgk_64_k66_modules.user` son los
   de la lista `mgk_64_device_modules` (`kernel/kleaf/mgx_64.bzl`).
   Declarar un `.ko` ahi hace que **el build falle si no se produce**: un
   build verde significa que el modulo existe.

## Tabla: que va donde

| Driver | Arbol | Config | Como llega al telefono |
|---|---|---|---|
| Panel m16 36-02-0b | GKI (ya portado) | `=y` | built-in |
| Tactil Focaltech FT3680 | GKI (ya portado) | `=y` | built-in |
| TEE Microtrust TEEI 400 | device modules | `=y` | built-in (como ruby) |
| mediatek_v2 | device modules | `=y` (v2) | built-in (via Makefile.ext) |
| Cargadores mp2762, ln8410, bq25980, sc8561, max77932, xmusb350 | portados al GKI | `=m` | modulos (`.ko`) |
| GNSS/GPU/camara (MTK) | `vendor/mediatek/kernel_modules` | `=m` | modulos |

**Nota sobre la v1 y la v2 de display**: si se compila la v2 (device
modules) hay que apagar la v1 del GKI (`CONFIG_DRM_MEDIATEK=n`), porque ambas
definen `mtk_dsi_*` y `mtk_disp_*`.

## Scripts que hacen el cableado

| Script | Que hace |
|---|---|
| `scripts/apply-ruby-fragment.sh` | mete los valores del config en el overlay de MTK, el defconfig y `sign.config` (el ultimo fragment del merge, gana sobre el overlay de TEEGRIS) |
| `scripts/patch-gki-mtk-drm.sh` | engancha los device modules al kbuild del GKI (`Makefile.ext`) |
| `scripts/patch-kleaf-outs.py` | declara los `.ko` en la lista de Kleaf |
| `scripts/patch-mtk-tee-config.sh` | cambia TEEGRIS por Microtrust 400 y arregla el include path de `geniezone` |
| `port/apply-all.sh` | aplica display, tactil, carga, TEE y config de una vez |

## El DTB de ruby casa con esos drivers

El overlay (`dtbo`) de ruby define los tres paneles y el tactil:

```
panel1@0  compatible = "m16_42_0d_0a_dsc_vdo,lcm"
panel2@0  compatible = "m16_36_02_0b_dsc_vdo,lcm"   <-- el panel de ruby
panel3@0  compatible = "m16_45_02_0c_dsc_vdo,lcm"
m16-touch@0 compatible = "focaltech,3680-spi", "goodix,9916r-spi"
```

Son exactamente los compatibles que usan los drivers del A34 (`m16_36_02_0b`
y `focaltech,3680-spi`), asi que **el DTB 6.6 que ya extraimos de ruby sirve
tal cual**: no hay que portar el Device Tree.

Los cargadores tambien estan en el overlay: `mp2762@5c`, `bq25980_standalone1..3`,
`sc8551_i2c7/11`, `sc8561_master/slave`, `ln8410_master/slave`, `max77932@68`,
`xmusb350@35` y `bq28z610@55` (fuel gauge).
