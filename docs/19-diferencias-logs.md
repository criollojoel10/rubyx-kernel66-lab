# 19 — Diferencias con el 6.6 privado y extracción de logs

## Qué es “el kernel privado 6.6”

Es el kernel stock de LineageOS 24 para ruby:

```
6.6.127-android15-8-4k-gf18ad88fac49-dirty
```

No tenemos su fuente: el repo público de RubyxLabs solo llega a 4.19. Lo que
hay es el **binario** dentro de `boot.img` y el `config` extraído por
IKCONFIG.

## Diferencias con el kernel mínimo

| Aspecto | 6.6 stock/privado | Mínimo actual |
|---|---|---|
| Fuente | RubyxLabs MTK 6.6 (privada) | UN1CA A34 6.6.127 |
| `Image` | 53 MB raw (21 MB gzip) | 38 054 400 B |
| Config | 8 626 líneas, 205 `CONFIG_MTK_*` built-in | GKI A34 + 11 módulos |
| Drivers MTK | todos built-in | 11 `.ko` en ramdisk |
| DTB | 179 139 B, 877 nodos, ruby | 197 665 B, base A34 + identidad ruby |
| Ramdisk | 20 651 368 B | 22 939 925 B con módulos |
| Almacenamiento | UFS/MMC built-in | **no incluido** |
| Pantalla/touch/carga | sí | **no incluido** |
| Android | arranca Android 17 | solo consola/earlycon |
| Namespaces | sin PID/IPC/SYSVIPC | tampoco (no se aplicó el fragmento) |
| AVB/firma | firmado, verity | imagen de prueba sin AVB |

El mínimo **no es** “el kernel privado pero compilado por nosotros”. Es un
kernel GKI de A34 con módulos de A34, un DTS basado en A34 y solo 11 módulos
de reloj/PMIC/pinctrl/watchdog/RTC. Sirve para validar el arranque, no para
Android.

## Cómo sacar logs sin Android

### 1. pstore/ramoops (ya funciona)

El dispositivo tiene:

```
/sys/fs/pstore/console-ramoops-0   262 132 B
```

Ese archivo contiene el log de un arranque anterior con
`4.19.325-Aeron-cip135`, no del 6.6 stock. Es la prueba de que **pstore
persiste entre reinicios**: el kernel 4.19 escribió y el 6.6 stock lo pudo
leer después.

El `Image` del A34 ya trae:

```
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
```

Por eso no hace falta recompilar para logs. El `boot.img` mínimo ahora pasa:

```
console=ttyS0,921600n8 earlycon
ramoops.mem_address=0x48090000
ramoops.mem_size=0xe0000
ramoops.pmsg_size=0x10000
ramoops.console_size=0x40000
```

Flujo:

1. arrancar el `boot.img` mínimo;
2. si falla o entra en pánico, reiniciar en caliente;
3. volver a flashear el `boot.img` stock;
4. arrancar Android;
5. leer:

```sh
ssh termux 'su -c "cat /sys/fs/pstore/console-ramoops-0"' > pstore.log
```

No hace falta Android “completo” para capturar el log: Android solo se usa
para **leer** la región de RAM reservada.

### 2. UART/earlycon

Si el kernel muere antes de que pstore inicialice, la única salida es UART:

```
console=ttyS0,921600n8 earlycon
```

Requiere acceso físico a los test points UART. Sin eso, los primeros
milisegundos no se pueden recuperar.

### 3. ADB / Android

No aplica al mínimo: no incluye UFS/MMC, USB gadget, display ni touch. ADB
llega en una fase posterior, cuando el kernel pueda montar `system/vendor`.

### 4. Logs del bootloader

`fastboot getvar`/LK pueden confirmar si el boot.img se cargó y si el DTB se
aceptó, pero no dan el log del kernel.

## Respuesta corta

- **No** hay que “usar todo en RAM y Android” para extraer logs.
- pstore ya está en RAM reservada y sobrevive al reinicio.
- Android solo hace falta para leer `/sys/fs/pstore`; el log lo escribe el
  kernel de prueba.
- Si el fallo es anterior a pstore, hace falta UART.

## Rollback

```
fastboot flash boot_a /root/ruby-gki/dl/boot.img
```

Ese boot es el stock; al flashearlo se pierde APatch hasta volver a parchear.
No se ha flasheado nada todavía.
