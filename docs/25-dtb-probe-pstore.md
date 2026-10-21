# 25 — El DTB ruby arranca y pstore funciona

## Test 4: sonda en el DTB stock

Se tomó el DTB stock de `boot_b` y se le añadió:

```
/reserved-memory/ruby-dtb-probe@48000000  (4 KiB, no-map)
```

Resultado en pstore:

```
OF: reserved mem: 0x0000000048000000..0x0000000048000fff
(4 KiB) nomap non-reusable ruby-dtb-probe
```

Eso prueba que **el bootloader usa el DTB del boot image**, no otro.

## Test 5: DTB ruby mínimo + pstore

Se partió de `dts/ruby-minimal.dtb` y se añadieron:

```
/reserved-memory/pstore@48090000      0xe0000  no-map
/reserved-memory/ruby-dtb-probe@48000000  4 KiB no-map
```

Imagen:

```
/tmp/ruby-diag2-rubydtb-pstore.img
sha256 e01a283db1f56f6bcdc44640c9904af27392109bfe27c0ebb25513e582eb2bc1
DTB sha256 62a3c1a3...
```

pstore:

```
Linux version 6.6.127-android15-8-abogkiA346BXXSEEZB6-4k
Machine model: MT6877V/TTZA        (el bootloader sobrescribe model)
OF: reserved mem: ... ruby-dtb-probe
OF: reserved mem: ... mblock-18-pstore
RUBYDIAG PID1_START
RUBYDIAG PSTORE kmsg=3 pmsg=4
...
RUBYDIAG MODULES_END
RUBYDIAG WATCHDOG_ARMED timeout=60
RUBYDIAG BOOT_DIAG_DONE returning_to_android
RUBYDIAG MISC_CMDLINE_NODE /dev/misc
RUBYDIAG MISC_OPEN_FAIL errno=6
```

pmsg confirma **11 MODULE_OK** y el watchdog a 60 s.

## Conclusión

- El DTB ruby propio **sí arranca**.
- La sonda `ruby-dtb-probe` y `mblock-18-pstore` demuestran que el DTB
  incluido en el boot image es el que usa el kernel.
- `Machine model` no sirve como marcador: el bootloader lo sobrescribe.
- pstore necesita el nodo `pstore@48090000` en el DTB; sin él, los logs del
  test anterior no se actualizaban.
- `MISC_OPEN_FAIL` sigue por falta de storage en el initramfs; el retorno a
  Android funciona por `tries=1`.

## Estado

```
boot_b stock   c9d6ad0d...  restaurado
misc stock     a1a43d22...  restaurado
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
```

## Siguiente

1. Añadir UFS/MMC al initramfs para que `misc` exista y el init pueda escribir
   el slot A (sin depender solo del fallback).
2. Empezar a recortar el DTB de A34 y añadir periféricos ruby.
3. Mantener `ruby-dtb-probe` y `pstore@48090000` en el DTB de trabajo.
