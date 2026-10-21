# 38 — Prueba de Droidspaces con APatch

## Regla de root

Para las pruebas en `ruby` se usa **APatch**, no Magisk.

- Superkey de APatch: **vacía**.
- Objetivo: `su -c 'id'` debe devolver `uid=0(root)` sin pedir clave.
- No se debe asumir root implícito: el script lo comprueba antes de seguir.

## Comprobación previa

Desde el host:

```sh
export APATCH_SUPERKEY=""
ssh termux 'su -c "id"'
```

Debe imprimir:

```text
uid=0(root) gid=0(root) context=u:r:magisk:s0
```

Si pide clave, hay que abrir APatch y dejar la superkey vacía; no continuar.

## Pruebas de kernel/Droidspaces

Con el kernel propio (PID/IPC/SYSVIPC built-in):

```sh
ssh termux 'su -c "
  echo === namespaces ===
  ls -l /proc/self/ns
  echo === unshare ===
  unshare -p -i -m -u -U true && echo UNSHARE_OK
  echo === cgroup ===
  mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
  cat /proc/self/cgroup
"'
```

Criterios:

- existen `pid`, `ipc`, `user`, `mnt`, `uts`, `net`, `cgroup`;
- `unshare -p -i -m -u -U true` devuelve 0;
- el contenedor de prueba puede arrancar un PID 1;
- no hay que introducir ninguna clave de APatch durante la prueba.

## Flujo de trabajo

1. Arrancar Android A con APatch y superkey vacía.
2. Verificar `su -c id`.
3. Flashear el kernel propio en `boot_b` con `tries=1`.
4. Arrancar Android desde B; si falla, el bootloader vuelve a A.
5. Ejecutar las comprobaciones de namespaces.
6. Si se prueba Droidspaces, usar el binario y el rootfs del proyecto, no un
   `su` interactivo.

El script `scripts/check-device-root.sh` automatiza el paso 2 y falla si APatch
pide clave o no concede root.
