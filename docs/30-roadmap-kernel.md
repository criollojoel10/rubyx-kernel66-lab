# 30 — Cómo llegar al kernel propio, Android y Droidspaces

## Dónde estamos

Ya está validado:

```
Kernel A34 6.6.127
11 módulos: clk, pinctrl, PMIC, RTC, watchdog, SPMI
DTB stock ruby + ruby-dtb-probe
dtbo 62/62 targets
pstore + pmsg
watchdog 60 s
retorno a Android por tries=1
```

Pero **no arranca Android**: faltan storage, display, touch y carga. El kernel
stock de ruby sigue siendo la única referencia funcional, y su fuente 6.6 no
es pública.

## La decisión de fondo

Hay dos caminos:

### A. Kernel source propio (necesario para Droidspaces)

Partir de 6.6.127 (A34/ACK) y portar los drivers ruby que faltan, o conseguir
la fuente privada del maintainer. Es el único camino para:

- añadir `PID_NS`, `IPC_NS`, `SYSVIPC`, `POSIX_MQ`;
- mantener los módulos GKI con el parche kABI;
- corregir GPS/consys y otros drivers desde fuente.

### B. Binario stock + módulos

Rápido para periféricos, pero **no sirve para Droidspaces**: el binario stock
no tiene código de PID/IPC namespaces y no se puede añadir con un `.ko`/KPM.
Descartado para el objetivo final.

**Conclusión:** hay que construir un kernel completo, no parchear el stock.

## Qué falta, por prioridad

### P0 — Storage (bloquea Android)

- Portar UFS/MMC de ruby 4.19 a 6.6 **sin** la cadena Samsung
  (`sec_ext`, `sec_debug`, `blocktag`) que hoy hace panic.
- Alternativa: portar `ufs-mediatek` del A34 eliminando sus dependencias
  Samsung.
- Criterio: `/dev/block/by-name/misc` y `super` existen en el initramfs;
  `MISC_OPEN_OK`; Android puede montar `system/vendor`.

### P1 — Pantalla, touch, carga

- DRM/DSI + paneles `m16_*` (el dtbo ya describe los nodos).
- `focaltech 3680` / `goodix 9916r` / `xiaomi-touch`.
- Cargadores `ln8000`, `bq25980`, `sc8551/8561`, `mtk_charger`,
  `pd_cp_manager`.
- Criterio: Android inicia con display y batería.

### P2 — USB/ADB, PMIC, audio

- USB gadget/ADB, reguladores MT6359, audio `aw882xx`, `mt6359-accdet`.
- Criterio: ADB y logcat estables.

### P3 — Cámara, fingerprint, GPS/consys, APU/GPU

- Sensores, ISP/VPU, Goodix/FPC, `consys`/GPS, Mali.
- Criterio: paridad funcional con el stock.

### P4 — Droidspaces

- Namespaces y cgroups en el defconfig propio.
- Criterio: `unshare -p/-i`, `/proc/self/ns`, `ip netns`, contenedor con
  PID 1.

## Droidspaces: configuración correcta

Fragmento seguro (kABI):

```
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_UTS_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_DEVTMPFS=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_MACVLAN=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
```

Aplicar antes de compilar:

```
droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
```

No activar `CGROUP_PIDS` ni `CFS_BANDWIDTH` sin un parche de padding kABI:
redimensionan `task_struct`/`cgroup` y rompen el CRC de miles de símbolos
exportados. Si se necesitan, se hace con el kernel propio y se reconstruyen
todos los módulos.

## Cómo se construye

1. `kernel/common` 6.6.127 + `kernel_device_modules` (A34/ACK).
2. `configs/ruby-6.6/ruby_defconfig` a partir del config stock extraído
   (8626 líneas) + fragmentos:
   - `droidspaces.fragment`
   - `storage.fragment`
   - `display.fragment`
3. Kleaf:
   ```
   PROJECT=ruby MODE=user ./build_kernel.sh
   ```
   target `mgk_64_k66`, `ruby_defconfig`.
4. Salida: `Image`, `Image.gz`, `.ko`, DTB.
5. Empaquetar con `scripts/build-diag-boot.py`:
   - DTB stock ruby + probe;
   - initramfs Android o diagnóstico;
   - boot header v2;
   - AVB footer del boot stock.
6. Probar en `boot_b` con `tries=1` y pstore.

## GPS y “otros”

GPS en MTK suele ser **consys + firmware + HAL**, no un driver ruby aislado.
Antes de tocar código hay que separar:

- `dmesg | grep -iE 'gps|consys|gnss'`;
- `logcat -b all -d | grep -iE 'gps|gnss|consys'`;
- nodo `gps` del dtbo y firmware en `/vendor/firmware`.

Si el fallo aparece en HAL/firmware, no se arregla portando el kernel. Si
aparece en `consys`/`gps` del kernel, se porta ese driver.

Lo mismo aplica a WiFi/BT, cámara y sensores: primero logs, después driver.

## Reality check

“Igual o mejor que el stock 6.6” no se consigue copiando el `Image` del A34:
hay que portar los drivers ruby o conseguir la fuente privada. El trabajo
grande es storage y display/touch/carga. Droidspaces es la parte fácil una vez
que el kernel propio arranca Android.
