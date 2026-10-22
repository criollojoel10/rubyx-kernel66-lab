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

## 2. Kleaf exige declarar los modulos nuevos

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
