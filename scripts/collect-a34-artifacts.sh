#!/usr/bin/env bash
# Recoge los artefactos reales del build. Falla si falta el Image.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="sources/a34x"
OUT="artifacts/a34-6.6.127"
DIST="$SRC/out/target/product/a34x/obj/KLEAF_OBJ/dist"

[ -d "$DIST" ] || { echo "falta $DIST; ¿falló el build?" >&2; exit 1; }
mkdir -p "$OUT"

log() { printf '[collect] %s\n' "$*" >&2; }

IMAGE="$(find "$DIST" -type f -path '*mgk_64_k66_kernel_aarch64.user/Image' -print -quit)"
if [ -z "$IMAGE" ]; then
  IMAGE="$(find "$SRC/out" -type f -name Image -size +1M -print -quit)"
fi
[ -n "$IMAGE" ] || { echo "no se encontró Image" >&2; exit 1; }
cp "$IMAGE" "$OUT/Image"
log "Image: $IMAGE"

# .config desde el propio Image (IKCONFIG)
if [ -x "$SRC/kernel-6.6/scripts/extract-ikconfig" ]; then
  if ! "$SRC/kernel-6.6/scripts/extract-ikconfig" "$OUT/Image" > "$OUT/config"; then
    log "AVISO: no se pudo extraer IKCONFIG del Image"
  fi
fi
[ -s "$OUT/config" ] || log "AVISO: config vacío o ausente"

copy_first() { # copy_first <nombre> <patrón find>
  local name=$1 pattern=$2 f
  f="$(find "$DIST" -type f -name "$pattern" -print -quit)"
  if [ -n "$f" ]; then
    cp "$f" "$OUT/$name"
    log "$name: $f"
  fi
}
copy_first Image.gz Image.gz
copy_first System.map System.map
copy_first vmlinux vmlinux
copy_first boot.img boot.img
copy_first boot-img.tar.gz boot-img.tar.gz
copy_first gki-info.txt gki-info.txt

# Module.symvers puede quedar en el árbol de Bazel, no en dist
SYM="$(find "$SRC/out" -type f -name Module.symvers -print -quit)"
if [ -n "$SYM" ]; then
  cp "$SYM" "$OUT/Module.symvers"
  log "Module.symvers: $SYM"
else
  log "AVISO: no se encontró Module.symvers en $SRC/out"
fi

DCFG="$(find "$SRC/out" -type f -path '*KLEAF_OBJ*' -name '.config' -print -quit)"
if [ -n "$DCFG" ]; then
  cp "$DCFG" "$OUT/device-modules.config"
  log "device-modules.config: $DCFG"
fi

# DTB/DTBO si el build los produce
found_dtb=0
while IFS= read -r -d '' f; do
  cp "$f" "$OUT/$(basename "$f")"
  found_dtb=1
done < <(find "$DIST" "$SRC/out" -type f \( -name '*.dtb' -o -name '*.dtbo' -o -name 'dtbo.img' -o -name 'dtb.img' \) -print0)

# Si no hay DTB suelto, mirar dentro de boot-img.tar.gz
if [ "$found_dtb" = 0 ] && [ -f "$OUT/boot-img.tar.gz" ]; then
  mkdir -p "$OUT/boot_tar"
  tar xzf "$OUT/boot-img.tar.gz" -C "$OUT/boot_tar"
  while IFS= read -r -d '' img; do
    if command -v unpack_bootimg >/dev/null 2>&1; then
      unpack_bootimg --boot_img "$img" --out "$OUT/boot_tar/$(basename "$img" .img)_unpacked" >/dev/null
    fi
  done < <(find "$OUT/boot_tar" -type f -name '*.img' -print0)
  while IFS= read -r -d '' f; do
    cp "$f" "$OUT/$(basename "$f")"
    found_dtb=1
  done < <(find "$OUT/boot_tar" -type f \( -name '*.dtb' -o -name 'dtbo' -o -name 'dtb' \) -print0)
fi

# Si no hay DTB suelto, extraerlo del boot.img del build
if [ "$found_dtb" = 0 ] && [ -f "$OUT/boot.img" ]; then
  if command -v unpack_bootimg >/dev/null 2>&1; then
    unpack_bootimg --boot_img "$OUT/boot.img" --out "$OUT/boot_unpacked" > "$OUT/boot-header.txt"
    if [ -f "$OUT/boot_unpacked/dtb" ]; then
      cp "$OUT/boot_unpacked/dtb" "$OUT/dtb"
      log "DTB extraído de boot.img"
    fi
  else
    log "AVISO: falta unpack_bootimg para extraer el DTB de boot.img"
  fi
fi

# Inventario de módulos y sus hashes (sin duplicar cientos de MB)
mapfile -d '' KOS < <(find "$DIST" -type f -name '*.ko' -print0)
if [ "${#KOS[@]}" -gt 0 ]; then
  sha256sum "${KOS[@]}" > "$OUT/modules.sha256"
  cp "${KOS[0]}" "$OUT/sample.ko"
  log "módulos: ${#KOS[@]} (muestra: $(basename "${KOS[0]}"))"
else
  log "AVISO: el build no produjo .ko"
fi

(
  cd "$OUT"
  : > sha256sums.txt
  for f in Image Image.gz config device-modules.config Module.symvers System.map vmlinux sample.ko boot.img dtb; do
    if [ -f "$f" ]; then
      sha256sum "$f" >> sha256sums.txt
    fi
  done
)

log "artefactos en $OUT"
ls -lh "$OUT"
