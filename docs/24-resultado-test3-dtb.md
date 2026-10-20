# 24 — Tercer intento: DTB ruby mínimo

## Qué se probó

`boot_b` con:

```
Image A34 6.6.127
initramfs diag2 (11 módulos)
dts/ruby-minimal.dtb (197 665 B)
```

Imagen:

```
/tmp/ruby-diag2-rubydtb.img
sha256 fe0c4b3b248afa8a79251179e14322bee938a97283cb72bf60594d488a4897fb
```

La imagen se escribió y verificó; slot B con `tries=1`; reboot.

## Resultado

El dispositivo volvió a Android A, pero **no hay evidencia de que el kernel
haya usado el DTB ruby**:

- `console-ramoops-0` y `pmsg-ramoops-0` son **idénticos byte a byte** a los
  del test 2 (hashes `23d75c4c...` y `26d3e517...`);
- el log sigue mostrando `Machine model: MT6877V/TTZA`, no
  `Xiaomi ruby (minimal)`;
- no aparecen nuevas marcas `RUBYDIAG` con otra sesión.

El estado del slot tras el intento era B `prio 0/tries 0`, A activo, lo que
indica que B no completó un boot válido y se agotó el intento.

No se puede distinguir todavía entre:

1. el bootloader rechazó/ignoró el DTB del boot image;
2. el kernel falló antes de pstore;
3. el DTB se usó pero el bootloader sobrescribió `model` y pstore no cambió.

## Estado restaurado

```
boot_b stock   c9d6ad0d...
misc stock     a1a43d22...
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
```

## Siguiente experimento

No seguir cambiando el DTB a ciegas. Hay que aislar el canal:

1. tomar el **DTB stock de ruby**;
2. añadirle una marca única e inocua (por ejemplo un nodo
   `reserved-memory` de 4 KiB con nombre `ruby-dtb-probe`);
3. compilar y bootear con el mismo initramfs;
4. verificar en pstore si aparece `ruby-dtb-probe`.

Si aparece, el DTB del boot image sí se usa y el problema es el contenido del
`ruby-minimal.dtb`. Si no aparece, el bootloader está usando otro DTB y hay que
investigar `dtb`/`dtbo`/`boot_para`.

No se ha flasheado nada después de restaurar.
