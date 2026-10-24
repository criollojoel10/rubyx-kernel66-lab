#!/usr/bin/env bash
# Prepara el ramdisk de ruby para una imagen de test:
#   - sustituye el init por el wrapper de primera etapa (watchdog que
#     devuelve al slot A si Android no arranca en 5 min)
#   - mete bctool (escritor de BCB para marcar el slot)
#
# Los drivers de ruby (display, tactil, huella, TEE) van built-in en el
# kernel, asi que aqui no se carga ningun .ko: solo los que traiga el
# ramdisk original mas lo que se pase explicitamente.
#
# Uso: ./scripts/pack-ramdisk-modules.sh <boot_unpacked> <moddir> <salida.lz4>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

UNPACKED="$(realpath -m "${1:?falta boot_unpacked}")"
MODDIR="$(realpath -m "${2:?falta directorio de módulos}")"
OUT="$(realpath -m "${3:?falta salida del ramdisk}")"

[ -f "$UNPACKED/ramdisk" ] || { echo "falta $UNPACKED/ramdisk" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

lz4 -d -f "$UNPACKED/ramdisk" "$TMP/ramdisk.cpio" >/dev/null
mkdir -p "$TMP/root"
(
  cd "$TMP/root"
  cpio -idm < "$TMP/ramdisk.cpio" 2>/dev/null

  # Recorta del ramdisk generico los binarios que solo usa recovery/fastbootd.
  # En boot normal init nunca los executa, y quitarlos baja el cpio ~10 MiB
  # (~4.5 MiB comprimido), que es el margen que necesita LZ4 para que el
  # payload quede por debajo de orig_size=41918464 (offset del vbmeta de
  # boot_b). Con gzip sobraba margen pero el arranque no llego al kernel;
  # LZ4 es el formato con el que la imagen SI arranco (v45/v46).
  # RUBY_RAMDISK_TRIM=0 lo desactiva.
  if [ "${RUBY_RAMDISK_TRIM:-1}" = "1" ]; then
    rm -f system/bin/recovery system/bin/update_engine_sideload \
          system/bin/fastbootd system/bin/snapuserd \
          system/lib64/librecovery_ui.so system/lib64/libncurses_recovery.so
  fi

  # modulos extra (si los hay)
  if [ -d "$MODDIR" ] && ls "$MODDIR"/*.ko >/dev/null 2>&1; then
    mkdir -p lib/modules
    cp "$MODDIR"/*.ko lib/modules/
    if [ -f "$MODDIR/modules.load" ]; then
      # RUBY_MODLIMIT=N: solo los N primeros modulos (biseccion de un crash
      # durante la carga; 0 = ninguno, para validar el loader en si).
      if [ -n "${RUBY_MODLIMIT:-}" ]; then
        head -n "$RUBY_MODLIMIT" "$MODDIR/modules.load" > lib/modules/modules.load
      else
        cp "$MODDIR/modules.load" lib/modules/
      fi
      # RUBY_MODLOADER_DRYRUN=1: el loader recorre la lista pero no carga nada.
      if [ "${RUBY_MODLOADER_DRYRUN:-0}" = "1" ]; then
        touch lib/modules/.dryrun
      fi
      # RUBY_MODLOADER_PROBE=1: el loader se cuelga si no aparece ningun
      # device de bloque en 6 s (senal de "UFS no probado" sin logs).
      if [ "${RUBY_MODLOADER_PROBE:-0}" = "1" ]; then
        touch lib/modules/.probe-block
      fi
      # RUBY_LOGSINK=1: el loader bifurca un hijo que vuelca /dev/kmsg a la
      # particion raw "oops" (sdc65), traza que sobrevive al reset y al boot A.
      if [ "${RUBY_LOGSINK:-0}" = "1" ]; then
        touch lib/modules/.log-sink
      fi
      # RUBY_WDT_SECS=N: el watchdog de diagnostico del loader dispara a los N
      # segundos (por defecto 60). El watchdog por hardware de MTK resetea
      # ~30 s, asi que hay que ponerlo mas corto para que el panic por sysrq-c
      # alcance a volcar el ring buffer a ramoops antes del reset.
      if [ -n "${RUBY_WDT_SECS:-}" ]; then
        printf '%s\n' "$RUBY_WDT_SECS" > lib/modules/.wdt-secs
      fi
      # RUBY_PANIC_SECS=N: tras cargar los modulos, el loader espera N s y fuerza
      # panic (sysrq-c) para volcar el ring buffer completo a ramoops. Sirve para
      # ver el estado real de UFS/display tras los probe diferidos.
      if [ -n "${RUBY_PANIC_SECS:-}" ]; then
        printf '%s\n' "$RUBY_PANIC_SECS" > lib/modules/.panic-secs
      fi
      # RUBY_PANIC_NOW=1: el loader hace _exit(42) como PID 1 en cuanto arranca
      # (beacon "Attempted to kill init" -> ramoops) para validar que se ejecuta.
      if [ "${RUBY_PANIC_NOW:-0}" = "1" ]; then
        touch lib/modules/.panic-now
      fi
    fi
  fi

  # Wrapper de primera etapa (watchdog que vuelve al slot A). Solo si se pide
  # explicitamente: necesita /system/bin/sh, que NO existe en el ramdisk de
  # primera etapa; con el wrapper el kernel muere con "Attempted to kill init".
  # El rollback de MTK ya devuelve a A cuando se agota el try del slot.
  if [ "${RUBY_INSTALL_WATCHDOG:-0}" = "1" ] && [ -f "$REPO/port/device/selfheal/first-stage-init.sh" ]; then
    # el init del ramdisk es un symlink a /system/bin/init (colgado aqui)
    if [ -L init ] || [ -e init ]; then
      mv -f init init.ramdisk 2>/dev/null || rm -f init
    fi
    cp "$REPO/port/device/selfheal/first-stage-init.sh" init
    chmod 755 init
    echo "  (init de primera etapa con watchdog instalado)"
  fi
  # Loader propio de /lib/modules: carga los .ko y deja el errno en /dev/kmsg
  # antes de ceder el testigo al init real. Util para saber por que falla
  # "Failed to load kernel modules" (init no imprime el errno).
  if [ "${RUBY_INSTALL_MODLOADER:-0}" = "1" ]; then
    SRC="$REPO/port/device/selfheal/module-loader.c"
    BIN="$REPO/port/device/selfheal/module-loader"
    if command -v aarch64-linux-gnu-gcc >/dev/null; then
      aarch64-linux-gnu-gcc -static -O2 -s -o "$BIN" "$SRC" || exit 1
    fi
    [ -x "$BIN" ] || { echo "falta module-loader (aarch64)" >&2; exit 1; }
    if [ -L init ] || [ -e init ]; then
      mv -f init init.ramdisk 2>/dev/null || rm -f init
    fi
    cp "$BIN" init
    chmod 755 init
    echo "  (init con loader de modulos instalado)"
  fi
  if [ -f "$REPO/port/device/selfheal/bctool" ]; then
    cp "$REPO/port/device/selfheal/bctool" bctool
    chmod 755 bctool
  elif [ -f "$REPO/port/device/selfheal/bctool.c" ] && command -v gcc >/dev/null; then
    gcc -O2 -static -o bctool "$REPO/port/device/selfheal/bctool.c"
    chmod 755 bctool
  fi

  # ficheros de init del GPS (stack GNSS de MTK 6.6) y de lo demas
  if [ -x "$REPO/scripts/pack-init-rc.sh" ]; then
    "$REPO/scripts/pack-init-rc.sh" . 2>/dev/null || true
  fi

  find . -print0 | cpio --null -o -H newc > "$TMP/new.cpio" 2>/dev/null
)
if [ "${RUBY_RAMDISK_GZIP:-0}" = "1" ]; then
  gzip -9 -n -c "$TMP/new.cpio" > "$OUT"
  gzip -t "$OUT"
else
  lz4 -l -12 -f "$TMP/new.cpio" "$OUT" >/dev/null
  lz4 -t "$OUT" >/dev/null
fi
n=0
[ -d "$MODDIR" ] && n=$(find "$MODDIR" -name '*.ko' 2>/dev/null | wc -l)
echo "ramdisk: $OUT ($(stat -c%s "$OUT") bytes, $n modulos)"
