# 99 — Errores del pipeline que ya han costado tiempo (y como evitarlos)

Recopilacion de los fallos que hicieron que un build "verde" no significase
nada. Todos estan resueltos y verificados; quedan aqui para no repetirlos.

## 1. El build verde no implica que el modulo exista

Sintoma: el build terminaba bien pero el `.ko` no aparecia y el simbolo de
config estaba como `# CONFIG_... is not set`.

Causa raiz: **el fragmento de config (`RUBY_OVERLAY`) nunca llegaba al
`.config` que compila los device modules**. El `.config` que se produce es el
de los device modules (`mgk_64_k66.user/.config`) y sus overlays son los que
pasa `gen_build_config.py`; nuestro `ruby_overlay.config` se copiaba a
`kernel_device_modules-6.6/kernel/configs/` pero no entraba en la lista.

Arreglo: `scripts/apply-ruby-fragment.sh` **edita directamente el overlay de
MTK** (`kernel_device_modules-6.6/kernel/configs/mt6877_overlay.config`),
que es el mecanismo que si funciona (es el mismo que usa el parche de
Microtrust para el TEE).

## 2. Kleaf tiene DOS listas y hay que tocar las dos

La lista que decide **que modulos se compilan** es
`mgk_64_device_modules` (en `kernel/kleaf/mgk_64.bzl`): si el modulo no
esta ahi, no se construye aunque el Kconfig lo deje en `m`. Y la lista que
decide **que ficheros se copian** son los `outs`
(`kernel/kleaf/mgk_modules.bzl`).

Por eso el `isee.ko` de Microtrust no aparecia (no estaba en la lista de
modulos) y despues daba "built but not copied" (no estaba en los outs).
`scripts/patch-kleaf-outs.py` toca las dos, y de paso cambia el TEEGRIS
510/515 por el Microtrust 400.

## 2 bis. Kleaf exige declarar los modulos nuevos

```
ERROR: The following kernel modules are built but not copied. Add these lines
to the outs attribute of @//kernel_device_modules-6.6:mgk_64_k66_modules.user:
    "drivers/tee/teei/400/isee.ko",
```

Arreglo: `scripts/patch-kleaf-outs.py` los añade a
`kernel/kleaf/mgk_modules.bzl` (`mgk_module_{user,eng,userdebug}_outs`).
Efecto bonus: como bazel exige que exista cada fichero declarado, **el build
falla si el modulo no llega a compilarse** -> la verificacion pasa a formar
parte del build.

## 2 bis. Los drivers de display/input/power van en el GKI, no en los device modules

En `kernel_device_modules-6.6/drivers/` **no hay Makefiles intermedios**
(`drivers/input/Makefile`, `drivers/gpu/drm/Makefile`, `drivers/power/Makefile`
no existen): el kbuild no puede descender a esos directorios, asi que los
drivers de display, tactil y alimentacion se compilan desde el **GKI**
(`kernel-6.6/drivers/...`), mientras que el TEE (TEEI) si vive en los device
modules.

Por eso nuestros ports de panel, tactil y carga tienen que aplicarse a
`sources/a34x/kernel-6.6` (GKI) y declarar sus simbolos en los Kconfig del
GKI. Si se aplican a los device modules, el .ko no se construye nunca y
Kleaf falla con "Unable to find <modulo>.ko".

Referencias que lo confirman (arbol MTK 6.6 publico de MT6877):

```
kernel_device_modules-6.6/drivers/input/Makefile        NO EXISTE
kernel_device_modules-6.6/drivers/gpu/drm/Makefile       NO EXISTE
kernel_device_modules-6.6/drivers/power/Makefile        NO EXISTE
kernel_device_modules-6.6/drivers/power/supply/Makefile EXISTE
kernel-6.6/drivers/{input,gpu/drm,power}/Makefile       EXISTEN
```

Es decir: en MTK 6.6 los drivers de display, tactil y alimentacion se
compilan desde el **GKI** (que produce `.ko` para los simbolos en `m`), y el
TEE (TEEI) desde los device modules. El target de Kleaf
`mgk_64_k66_modules.user` tiene como `outs` la lista
`mgk_64_device_modules`, y su staging es compartido, asi que un `.ko`
compilado en el GKI tambien se recoge si esta en esa lista.

Validado en local reproduciendo el merge exacto del build:

```
CONFIG_DRM_PANEL_M16_36_02_0B_DSC_VDO=m
CONFIG_TOUCHSCREEN_FOCALTECH_3680=m
CONFIG_RUBY_MP2762=m ... CONFIG_RUBY_XMUSB350=m
CONFIG_MICROTRUST_TEE_SUPPORT=m
CONFIG_MICROTRUST_TEE_VERSION="400"
```

## 3. Los simbolos nuevos tienen que ser visibles en el Kconfig

Un `config` anadido al `Kconfig` de un subdirectorio puede no llegar al
arbol que se parsea. Ahora los simbolos de nuestros ports se declaran en
`kernel_device_modules-6.6/Kconfig.ext` (el fichero que siempre se sourcea),
y el `source` de los Kconfig por subdirectorio se deja como estaba.

## 4. Verificar despues de recoger

Los workflows de panel/touch/charger fallaban en la verificacion porque no
tenian el paso `make collect` (que genera `device-modules.config` y el
tarball de modulos). Ahora todos los builds hacen `make collect` antes de
verificar.

## 5. Comprobaciones rapidas antes de un build de 40 minutos

- `scripts/unify-ci-cache.py`: deja una sola clave de cache compartida. Sin
  esto cada build era en frio (~39 min) porque cada workflow tenia su
  prefijo y el sha iba en la clave primaria.
- Workflow `check-kconfig.yml`: parsea el Kconfig real y comprueba que
  nuestros simbolos existen y valen `m` (2-3 min).
- `scripts/patch-kleaf-outs.py --check` para ver los modulos declarados.

## 6. Comprobaciones de seguridad del script de parcheo

Dos veces un parche "aplicado" no lo estaba:

- el check de idempotencia buscaba `drivers/tee/tzdev/` y coincidia con la
  rama TEEGRIS original del propio Makefile;
- el check de presence buscaba `drivers/tee/tzdev/$(CONFIG_TEEGRIS_VERSION)...`
  y coincidia con una linea que ya existia.

Regla: usar un **marcador propio** (comentario único) para detectar si el
parche esta puesto, y no una cadena que ya exista en el fichero.
