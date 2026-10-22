#!/usr/bin/env bash
# Compila un target del kernel y resuelve solo los headers que falten,
# copiandolos al GKI desde los arboles de origen (device modules o el arbol
# publico de MTK 6.6). Es lo que hace falta al portar drivers de MTK: la
# mediatek_v2 y el TEEI 400 arrastran headers UAPI/soc que el GKI del A34
# no trae.
#
# Uso: scripts/build-target-local.sh <ruta-relativa-del-target> [intentos]
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

TARGET="${1:?falta el target}"
INTENTOS="${2:-12}"

# rutas absolutas: el script cd al GKI y las rutas de origen deben seguir
# valiendo
GKI="$(cd sources/a34x/kernel-6.6 && pwd)"
DM="$(cd sources/a34x/kernel/kernel_device_modules-6.6 && pwd)"
VOLLA="$(cd sources/mtk-6.6-mt6877/kernel_device_modules 2>/dev/null && pwd || echo /nonexistent)"

[ -d "$GKI" ] || { echo "falta $GKI; ejecuta make fetch" >&2; exit 1; }
export KCONFIG_EXT_PREFIX=../kernel/kernel_device_modules-6.6/

cd "$GKI"
for i in $(seq 1 "$INTENTOS"); do
  out=$(timeout 1800 make -j"$(nproc)" CC=gcc HOSTCC=gcc "$TARGET" 2>&1)
  if [ $? -eq 0 ] && ! echo "$out" | grep -qE '(^|:) error:'; then
    echo "[build] $TARGET: OK"
    exit 0
  fi

  hdr=$(echo "$out" | grep -oE "fatal error: [^:]+: No such file" | head -1 | sed 's/fatal error: //; s/: No such file//')
  if [ -z "$hdr" ]; then
    echo "[build] $TARGET: FALLO (no es un header lo que falta)"
    echo "$out" | grep -E '(^|:) error:|Error [0-9]|undefined reference' | head -20 | sed 's/^/    /'
    exit 1
  fi

  # buscar el header en los arboles de origen
  found=""
  for root in "$DM" "$VOLLA" "$GKI"; do
    [ -d "$root" ] || continue
    f=$(find "$root" -path "*/$hdr" -not -path "*/.git/*" 2>/dev/null | head -1)
    if [ -n "$f" ]; then found="$f"; break; fi
  done
  if [ -z "$found" ]; then
    echo "[build] no encuentro el header: $hdr"
    echo "$out" | grep -E 'fatal error' | head -5 | sed 's/^/    /'
    exit 1
  fi

  # los headers que se incluyen con <linux/...> o <uapi/...> van a
  # include/ del GKI (el kernel anade $(srctree)/include al include path)
  case "$hdr" in
    linux/*|uapi/*) dest="$GKI/include/$hdr" ;;
    *)            dest="$GKI/$hdr" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp -a "$found" "$dest"
  echo "[build] copiado $hdr  (desde ${found#$ROOT/})"
done

echo "[build] se agotaron los intentos"
exit 1
