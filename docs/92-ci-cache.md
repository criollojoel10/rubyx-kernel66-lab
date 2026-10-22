# 92 — Cache de CI: diagnostico y arreglo

## Sintoma

Todos los builds tardaban **~39 min en el paso "Build core"**, sin importar
cuantas veces se repetia el mismo arbol, y el log de Actions mostraba:

```
Caché Bazel + Clang  Cache not found for input keys:
  ds-a34-<manifest>-<overlay>-<sha>, ds-a34-<manifest>-
```

Es decir: **la cache nunca se restauraba**; cada ejecucion era un build en
frio de Bazel.

## Causa (verificada en los logs y en la API de caches)

1. Cada workflow usaba **su propio prefijo** de cache:

   ```
   ds-    (droidspaces)          core-   (core)
   kabi-  (droidspaces + kABI)   mt-     (microtrust)
   panel- (panel m16)            fast-   (build rapido)
   storage-                       bazel-  (referencia)
   ```

   El cache de acciones de Bazel es **el mismo para todos** (mismo arbol
   A34, mismo clang r536225, mismo `KBUILD_BUILD_TIMESTAMP` fijado), asi que
   un workflow deberia poder reutilizar el de otro. Con prefijos distintos
   no era posible.

2. La clave primaria llevaba `${{ github.sha }}`, por lo que cada commit
   generaba una clave nueva. Correcto para guardar instantaneas, pero
   obligaba a depender de `restore-keys` para recuperar algo.

3. Los caches ocupaban ~2 GB cada uno y habia 5-6 en el repo: cerca del
   limite de 10 GB de GitHub, lo que provoca **evictions** (el cache mas
   antiguo, `fast-` del 2026-10-20, es el primero en caer).

## Segundo fallo: los prefijos de respaldo no casaban

Unificar los prefijos no basto: los caches historicos se llaman
`<workflow>-a34-<hash manifest>-<sha>` (p. ej. `ds-a34-951210ca…-ed77ffa…-7192c85…`)
pero los `restore-keys` que generaba el script eran `ds-<hash manifest>-`,
`core-<hash manifest>-`… es decir **les faltaba el infijo `a34-`**, asi que
ningun prefijo podia coincidir con ninguna clave real.

Se comprobo con un workflow de diagnostico (`diagnose-cache.yml`) que imprime
el resultado de la busqueda: con los prefijos mal escritos la accion decia

```
Cache not found for input keys: diag-a34-<hash>-<sha>
```

y con los prefijos correctos:

```
Cache Size: ~1606 MB (1683932674 B)
Cache restored successfully
Cache restored from key: ds-a34-<hash manifest>-ed77ffa…
1.2G    /home/runner/.cache/bazel-disk
3.6G    /home/runner/.cache/ruby
```

## Arreglo

`scripts/unify-ci-cache.py` reescribe los 9 workflows:

- clave primaria: `a34-<hash manifest>-[<hash extra>]-<sha>`
  (guarda una instantanea nueva en cada ejecucion);
- `restore-keys`: primero el prefijo compartido `a34-<hash manifest>-` y
  despues los prefijos historicos (`ds-`, `core-`, `kabi-`, `mt-`, `panel-`,
  `fast-`, `storage-`, `bazel-`, `bazel-pilot-`) para reutilizar de
  inmediato los caches ya existentes.

Con eso, la primera ejecucion tras el arreglo restaura el cache mas reciente
sea del workflow que sea, y todas las siguientes comparten el mismo.

## Coste real de un build

Medido en el run `39695857422` (exito, subsistema seguro de Droidspaces):

| Paso | Tiempo |
|---|---|
| Liberar espacio (apt purge) | 2 m 09 s |
| Dependencias | 12 s |
| Cache Bazel + Clang | 0 s (fallo de cache) |
| Fetch A34 | 1 m 22 s |
| **Build core (Bazel)** | **39 m 15 s** |
| Recolectar + verificar | 30 s |
| Subir artefactos | 22 s |

El 90 % del tiempo es Bazel. Con la cache restaurada, solo se recompilan
las acciones afectadas por el overlay (el resto sale del cache de
disco), por lo que el build debe bajar a **~10-15 min**.

## Tareas periodicas

- Si el repo se acerca a 10 GB de caches, borrar los antiguos:
  ```sh
  gh api repos/criollojoel10/rubyx-kernel66-lab/actions/caches --jq \
    '.actions_caches[] | "\(.id) \(.created_at) \(.key)"'
  gh api -X DELETE repos/criollojoel10/rubyx-kernel66-lab/actions/caches/<id>
  ```
