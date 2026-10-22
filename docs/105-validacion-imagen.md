# 105 — Validación de la imagen de ruby antes de flashear

Todo esto se puede comprobar **en local**, sin dispositivo y sin build de CI.

## 1. El DTB final (base 6.6 + dtbo de ruby)

El bootloader de ruby aplica el `dtbo` de la particion `dtbo` sobre el DTB
base que va dentro del `boot.img`. Los dos estan extraidos:

```sh
fdtoverlay -i /root/ruby-gki/work/dtb_boot/01_dtbdump_MT6877.dtb \
           -o /tmp/dtb-fused.dtb \
           /root/ruby-gki/work/dtbo_parts/01_dtbdump_RUBY.dtb
dtc -I dtb -O dts /tmp/dtb-fused.dtb > /tmp/dtb-fused.dts
```

Compatibles que tiene que tener el DTB final (todos verificados):

| Compatible | Driver que lo necesita |
|---|---|
| `m16_42_0d_0a_dsc_vdo,lcm` | panel m16 42-0d-0a (`port/display`) |
| `m16_36_02_0b_dsc_vdo,lcm` | panel m16 36-02-0b (`port/display`) |
| `focaltech,3680-spi` | tactil FT3680 (`port/touch`) |
| `awinic,aw882xx_smartpa` | altavoz (`port/audio`) |
| `mediatek,mt6877-disp-ovl` | mediatek_v2 (copiada al GKI) |
| `mediatek,speaker-codec` | card de sonido MT6877 |
| `mediatek,mt6877-mt6359-sound` | card de sonido MT6877 |
| `goodix,goodix-fp` | huella (`port/fingerprint`) |
| `lionsemi,ln8000`, `mp2762` | cargadores (el A34 ya trae equivalentes) |

Si alguno falta, el driver correspondiente no instancia y la cadena
(panel -> tactil -> TEE) no llega.

## 2. La imagen

```sh
./scripts/build-ruby-boot.sh --artifacts artifacts/a34-6.6.127 --out /tmp/ruby.img
```

Resultado esperado:

```
payload 36.947.968 bytes  <  vbmeta offset 41.918.464   -> cabe
imagen 134.217.728 bytes (128 MB)
AVB footer conservado
```

El limite de 41,9 MB es el offset del vbmeta: si el payload lo pasa, el
bootloader firma/rechaza y no arranca.

## 3. Lo que lleva dentro

- **kernel**: el `Image.gz` del build (los drivers de ruby van built-in, no
  son `.ko`).
- **ramdisk**: el stock de ruby con el `init` sustituido por el wrapper de
  primera etapa (watchdog que vuelve al slot A si Android no confirma el
  arranque en 5 min) y el `bctool`.
- **DTB**: `01_dtbdump_MT6877.dtb` (el 6.6 de ruby), sin tocar.

## 4. El flash

```sh
./scripts/test-ruby-kernel.sh <run-id>
```

Hace: descarga el artefacto del run, monta la imagen, la escribe en
`boot_b` (con readback y hash), marca el slot B con `tries=1` y reinicia.
Si Android no arranca en 5 min, el watchdog del ramdisk devuelve al slot A.

Despues: `./scripts/verify-ruby.sh` comprueba imagen, tactil, TEE, huella,
carga, audio, GPS y los requisitos de Droidspaces.
