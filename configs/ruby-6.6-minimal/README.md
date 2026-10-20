# ruby-6.6-minimal

Fragmento de configuración para el primer arranque de ruby sobre el BSP 6.6
del A34.

No es un `defconfig` completo. Se aplica como overlay sobre
`mediatek-bazel_defconfig` + `mt6877_overlay.config`:

```
ruby_earlycon.fragment
```

Incluye:

- consola 8250 MT6577;
- MMC/UFS MediaTek;
- PMIC MT6397 + RTC;
- watchdog MediaTek;
- IOMMU, clocks y pinctrl MT6877;
- PID/IPC/UTS/NET/USER namespaces, SYSVIPC, POSIX MQ, cgroups, seccomp,
  overlayfs, veth, bridge y netfilter para Droidspaces.

## Validación

```sh
make check-config
```

Comprueba que los 36 `CONFIG_*` existan en los Kconfig del A34. Todos existen
hoy. Todavía **no** se ha compilado el kernel con este fragmento: la
validación real es la Fase 5.
