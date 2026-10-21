# 26 — Storage en el initramfs: bloqueado por módulos Samsung

## Objetivo

Añadir UFS/IOMMU al initramfs para que el kernel registre `/dev/block/...`,
`find_partition("misc")` funcione y el PID 1 pueda escribir el slot A sin
depender del fallback.

## Cierre calculado

Con las raíces:

```
phy-mtk-ufs, ufs-mediatek-mod, mtk_iommu
```

el cierre es de **29 módulos**. Incluye la cadena de Samsung:

```
ufs-mediatek-mod -> ufs-mediatek-dbg, irq-dbg, abc,
                    sec_debug, sec_ext, blocktag, rpmb
```

## Resultado

El kernel arrancó con el DTB stock y el cmdline stock (sin overflow), pero al
cargar `sec_ext`:

```
Unable to handle kernel paging request ...
pc : sysfs_create_svc_ap+0x18/0x154 [sec_ext]
lr : chipid_sysfs_init+0x54/0x154 [sec_ext]
Internal error: Oops ... [#1] PREEMPT SMP
Kernel panic - not syncing: Oops: Fatal exception
```

`sec_ext` es un módulo de Samsung del A34; asume nodos/sysfs que no existen
en ruby y tumba el kernel. No es un problema del DTB ni del init.

Después del pánico, el slot B agotó su intento y volvió Android A.

## Cmdline

El `cmdline overflow` anterior se resolvió usando **exactamente** el cmdline
stock en el boot image:

```
bootopt=64S3,32N2,64N2 androidboot.tee_type=2
```

y dejando que el DTB stock aporte el resto (`root=/dev/ram`, consola,
ramoops). Con eso el kernel booteó (hasta el pánico de `sec_ext`).

## Decisión

- **No** usar la cadena UFS del A34: arrastra `sec_ext`/`sec_debug` y no es
  compatible con ruby.
- Mantener el initramfs de **11 módulos**.
- Aceptar el retorno por fallback `tries=1`; ya funcionó en los tests 1–5.
- Para escribir el BCB haría falta portar UFS/MMC sin dependencias Samsung o
  usar otro mecanismo; no bloquea el bring-up.

## Estado

```
boot_b stock   c9d6ad0d...  restaurado
misc stock     a1a43d22...  restaurado
slot A activo, B prio 14/tries 1/success 1
Android 17, boot_completed=1
```

## Siguiente

Seguir con el DTB/periféricos, no con storage A34. El DTB ruby ya está
validado con `ruby-dtb-probe` y pstore; el siguiente trabajo es recortar
nodos A34 y añadir los ruby.
