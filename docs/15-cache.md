# 15 — Caché de builds

## Medición del build de referencia

Run 5 (A34 6.6.127, 56m 19s):

| Etapa | Tiempo aproximado |
|---|---:|
| `repo sync` | 1m 20s |
| descarga/extracción Clang r536225 | ~6m |
| Kleaf/Bazel | ~43m |
| recolección/verificación | <1m |

La caché de Bazel se restauró (613 MB), pero solo dio **4 hits de 524
acciones**. La causa es `--config=stamp`: el script fija
`SOURCE_DATE_EPOCH="$(date +%s)"`, así que la clave de casi todas las acciones
cambia en cada run.

## Mejoras aplicadas

`scripts/build-a34-fast.sh` genera una copia del script oficial y:

1. **Fija `SOURCE_DATE_EPOCH=1700000000`** en los tres puntos donde el A34 usa
   la hora actual (`_setup_env.sh`, `stamp.bzl`, `gen_build_config.py`).
   Esto hace estables las claves de acción.
2. **Cachea Clang r536225** en `~/.cache/ruby/clang-r536225`. Si existe, se
   copia al árbol AOSP y se evita la descarga/extracción de ~6m.
3. **Permite reutilizar `aosp-kernel`** (`mkdir -p`), de modo que un
   `repo sync` incremental no reconstruye el workspace.
4. Mantiene `--disk_cache=$HOME/.cache/bazel-disk` y el
   `actions/cache` de Bazel + Clang.

Workflow: `build-a34-fast.yml`.

## Qué esperar

| Run | Clang | Bazel | Comentario |
|---|---|---|---|
| 1 (frío) | descarga | cold | guarda caché |
| 2 | cache hit | claves estables | debería bajar varios minutos |
| 3+ | cache hit | acción reutilizada | objetivo |

No se puede prometer un tiempo hasta medir el run 2. El caché no cambia el
resultado del kernel, solo evita repetir trabajo.

## Límites

- **ccache no aplica**: Kleaf no lo soporta; el equivalente es la caché de
  acciones de Bazel.
- **GitHub cache** tiene un límite de 10 GB por entrada. `KLEAF_OBJ`
  completo puede superarlo; por eso no se cachea todavía.
- **`repo sync`** sigue consultando red; se mitiga reutilizando el workspace.
- **Firma/stamping**: fijar `SOURCE_DATE_EPOCH` es válido para desarrollo, pero
  un build de release debe usar el epoch real o el del OSRC.

## Próximas opciones

1. Cachear `aosp-kernel/prebuilts` completo (no solo Clang) si el tamaño cabe.
2. Cachear el `output_base` de Bazel para builds incrementales.
3. Añadir `--repository_cache` para dependencias externas.
4. Medir el run 2 antes de añadir más capas.
