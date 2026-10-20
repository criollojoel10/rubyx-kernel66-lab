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

IMAGE="$(find "$DIST" -type f -path '*mgk_64_k66_kernel_aarch64.user/Image' | head -1)"
if [ -z "$IMAGE" ]; then
  IMAGE="$(find "$SRC/out" -type f -name Image -size +1M | head -1)"
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
  f="$(find "$DIST" -type f -name "$pattern" | head -1)"
  if [ -n "$f" ]; then
    cp "$f" "$OUT/$name"
    log "$name: $f"
  fi
}
copy_first Image.gz Image.gz
copy_first Module.symvers Module.symvers
copy_first System.map System.map
copy_first vmlinux vmlinux

# DTB/DTBO si el build los produce
while IFS= read -r -d '' f; do
  cp "$f" "$OUT/$(basename "$f")"
done < <(find "$DIST" "$SRC/out" -type f \( -name '*.dtb' -o -name '*.dtbo' -o -name 'dtbo.img' -o -name 'dtb.img' \) -print0)

# Inventario de módulos y sus hashes (sin duplicar cientos de MB)
mapfile -d '' KOS < <(find "$DIST" -type f -name '*.ko' -print0)
if [ "${#KOS[@]}" -gt 0 ]; then
  sha256sum "${KOS[@]}" > "$OUT/modules.sha256"
  cp "${KOS[0]}" "$OUT/sample.ko"
  log "módulos: ${#KOS[@]} (muestra: $(basename "${KOS[0]}"))"
else
  log "AVISO: el build no produjo .ko"
fi

: > "$OUT/sha256sums.txt"
for f in Image Image.gz config Module.symvers System.map vmlinux sample.ko; do
  if [ -f "$OUT/$f" ]; then
    sha256sum "$OUT/$f" >> "$OUT/sha256sums.txt"
  fi
done

log "artefactos en $OUT"
ls -lh "$OUT"
