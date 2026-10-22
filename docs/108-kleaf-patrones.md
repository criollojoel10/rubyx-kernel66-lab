# Kleaf: cómo se declaran los módulos del vendor

Explica por qué fallan `built but not copied` y `no such target …customer_modules_install.user`,
y cuál es la forma segura de tocar las listas. Corrige lo que decía `docs/99` §2.

## 1. Quién manda en cada lista

- `kernel_device_modules-6.6/build/bazel_mgk_rules/mgk.bzl:378` genera los
  nombres: `"{name}_customer_modules_install.{build}"` →
  `mgk_64_k66_customer_modules_install.user`.
- `BUILD.bazel` **no** contiene ningún `module_outs`: solo carga listas y llama
  a `define_mgk(...)`.
- `kernel/kleaf/mgk_modules.bzl` define las listas del **árbol GKI**
  (`mgk_module_outs` = `get_gki_modules_list("arm64")`) y
  `mgk_module_{eng,userdebug,user}_outs = mgk_module_ext_outs + [...]`.
- `kernel/kleaf/mgk_64.bzl` define lo que construye el **árbol de device
  modules**:
  - `mgk_64_device_modules = mtk_device_modules + lego_module_list +
    samsung_device_modules`;
  - `mgk_64_platform_device_modules`, un dict `{ko: "plat1 plat2"}` filtrado
    por `*/mgk.enabled`;
  - **`mgk_64_module_outs = []`** (línea ~126), que se funde en las **cuatro**
    variantes `mgk_64_common_*`. Es el único ancla segura.
- La comprobación de Kleaf (`build/kernel/kleaf/impl/kernel_build.bzl:1116-1169`)
  compara los `.ko` realmente producidos contra `module_outs` +
  `module_implicit_outs` **del mismo target**. Por eso `define_mgk`
  (`mgk.bzl:227` frente a `253`) mapea `user`→`ack` en el árbol GKI
  (`module_outs=[]`, `module_implicit_outs=common_modules`) y
  `user`→`module_implicit_outs=common_user_modules` en el de device modules.
- Los `.ko` llegan a `/lib/modules` por un `kernel_module(name=
  "{name}_modules.{build}", outs=real_device_modules + …)` (`mgk.bzl:453-471`),
  donde `real_device_modules` = `get_real_modules_list()` y va **filtrado por
  glob**: una entrada cuyo directorio no existe se descarta en silencio, y una
  cuyo directorio existe pero no produce `.ko` falla como output perdido.
- `CONFIG_DEVICE_MODULES_*` no es un prefijo que Kleaf añada: es un renombrado
  literal de MTK en los Kconfig/Makefiles del vendor
  (`drivers/power/supply/Kconfig:188: config DEVICE_MODULES_CHARGER_MT6360`).
  Los símbolos sin prefijo (p. ej. `CONFIG_MICROTRUST_TEE_SUPPORT`) son de
  Kconfigs que el GKI también lee.
- El "plus-config" es `artifacts/a34-6.6.127/device-modules.config`: el
  `.config` fusionado del árbol de device modules. Los overlays llegan ahí solo
  por `kernel/configs/mt6877_overlay.config` + `sign.config` +
  `arch/arm64/configs/mediatek-bazel_defconfig`.

## 2. La forma segura de declarar un `.ko`

En `kernel/kleaf/mgk_64.bzl`, sustituir la lista vacía (es top-level, así que
no puede romper la indentación de un `def`):

```python
mgk_64_module_outs = [
    # ruby: .ko que el arbol de device modules produce y Kleaf debe declarar
    # (silencia "built but not copied"); una entrada por linea.
    # "drivers/tee/teei/400/isee.ko",
]
```

Y si además hay que **copiarlo** a `/lib/modules`, añadir la misma ruta una vez
a `mgk_64_device_modules` (va filtrada por glob: tiene que compilarse de
verdad).

Nunca:

- añadir bloques `_ruby_add`/`_ruby_remove` al final del fichero,
- reescribir los límites de las listas con `re.sub`,
- tocar los brazos `select()` de `define_mgk`.

Eso es lo que produjo `expected an indented block` y la desaparición de
`//kernel_device_modules-6.6:mgk_64_k66_customer_modules_install.user`.

## 3. Cómo lo hace Volla (mismo SoC, 6.6.89, arranca)

- `mgk_modules.bzl` **prístino**: `mgk_module_user_outs = mgk_module_ext_outs + []`.
- `mgk_64_module_outs = []`.
- `mgk_64_device_modules` sí lista `drivers/tee/teei/510/isee.ko`,
  `../510/isee-ffa.ko`, `drivers/tee/teeperf/teeperf.ko`,
  `drivers/tee/gud/610/…`, `drivers/input/fingerprint/goodix-gw9518/gf_tee.ko`.
- La versión del TEE se elige con un overlay de 36 bytes,
  `kernel/configs/isee400_overlay.config` = `CONFIG_MICROTRUST_TEE_VERSION="400"`,
  sin tocar defconfig ni `sign.config`.
- Audio y cámara también como módulos: `CONFIG_SND_SOC_MT6877=m`,
  `CONFIG_SND_SOC_MT6877_MT6359P=m`, `CONFIG_SND_SOC_AW883XX=m`,
  `CONFIG_MTK_CAMERA_*_ISP6S=m`.

Patrón: **TEE/audio/cámara van en la lista de device modules, los outs no se
tocan**.

## 4. Qué hacemos nosotros

Mantener las puertas built-in para TEE y audio:

- coincide con el kernel stock de ruby (todo `=y`, sin `.ko`);
- evita cirugía de `module_outs` y el fallo `built but not copied`;
- el CI ya comprueba que `teei/400/isee.ko` **no** está en el tarball.

Coste: no se pueden recargar en caliente ni pasar parámetros por módulo, y
droidspaces ve menos módulos. Aceptable: los drivers tampoco son extraíbles en
la imagen stock.

Declarar `module_outs` solo para drivers del vendor que de verdad deban ser
módulos (p. ej. si droidspaces necesita cargarlos). Cada entrada es un
contrato de build: si el `.ko` no se produce, el build falla.

## 5. Sustituto seguro de `patch-kleaf-outs.py --dm`

El script actual mete cualquier argv en las listas: hoy
`sources/a34x/kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_modules.bzl`
tiene `"--help"` como si fuera un `.ko` (prueba de ello; el árbol local está
gitignored, así que no es diffeable ni revertible).

Especificación:

1. Leer el fichero y emparejar el ancla exacta de dos líneas
   `mgk_64_module_outs = [\n]`; si no está y ya existe el marcador
   `# ruby: .ko`, no hacer nada; si no está y no existe, **abortar sin
   escribir**.
2. Rechazar cualquier argumento que no acabe en `.ko`
   (`if not a.endswith(".ko"): sys.exit(...)`).
3. Tras escribir: `python3 -m py_compile` del fichero y
   `bazel query //kernel_device_modules-6.6:mgk_64_k66_customer_modules_install.user`
   (o `buildifier -mode=check`) antes del build completo; restaurar el `.bak`
   si falla.
4. Para builds exploratorios, preferir `--allow_undeclared_modules`
   (`build/kernel/kleaf/BUILD.bazel:266`), que convierte el ERROR en WARNING,
   antes que editar listas.

## 6. Corrección a `docs/99` §2

`docs/99-pitfalls-pipeline.md` §2 dice que los `.ko` del árbol de device
modules se declaran en `mgk_modules.bzl`. **No es así**: ese fichero es del
árbol GKI y Volla lo deja vacío. Lo que construye y declara el árbol de device
modules es `mgk_64_device_modules` / `mgk_64_module_outs` en
`kernel/kleaf/mgk_64.bzl`, y el staging a `/lib/modules` va por
`kernel_module(...)` con la lista filtrada por glob.
