#!/usr/bin/env bash
# Clona el tag de referencia del A34 y su submódulo, fijados por commit.
# Idempotente: si ya existe, verifica; no cambia de revisión en silencio.
set -euo pipefail
cd "$(dirname "$0")/.."

LOCK="manifests/a34-6.6.127.lock.json"
read_lock() { python3 -c "import json,sys;d=json.load(open('$LOCK'));print(eval(sys.argv[1]))" "$1"; }

REPO="$(read_lock "d['reference']['repo']")"
TAG="$(read_lock "d['reference']['tag']")"
COMMIT="$(read_lock "d['reference']['commit']")"
SUB_URL="$(read_lock "d['reference']['submodules'][0]['url']")"
SUB_COMMIT="$(read_lock "d['reference']['submodules'][0]['commit']")"
DEST="sources/a34x"

log() { printf '[fetch] %s\n' "$*" >&2; }
die() { printf '[fetch] ERROR: %s\n' "$*" >&2; exit 1; }

if [ -d "$DEST/.git" ]; then
  log "existe $DEST; verificando"
  head_sha="$(git -C "$DEST" rev-parse HEAD)"
  [ "$head_sha" = "$COMMIT" ] || die "$DEST está en $head_sha, se esperaba $COMMIT. Bórralo para recargar."
else
  log "clonando $REPO en $TAG"
  mkdir -p sources
  git clone --depth 1 --branch "$TAG" "$REPO" "$DEST"
  head_sha="$(git -C "$DEST" rev-parse HEAD)"
  [ "$head_sha" = "$COMMIT" ] || die "tag $TAG resolvió a $head_sha, se esperaba $COMMIT"
fi

log "submódulo kernel-6.6"
if ! git -C "$DEST" submodule update --init --depth 1 kernel-6.6; then
  log "el fetch superficial falló; reintentando sin --depth"
  git -C "$DEST" submodule update --init kernel-6.6
fi
sub_sha="$(git -C "$DEST/kernel-6.6" rev-parse HEAD)"
[ "$sub_sha" = "$SUB_COMMIT" ] || die "submódulo en $sub_sha, se esperaba $SUB_COMMIT"

# El .gitmodules del tag declara un 'branch' que en realidad es un SHA.
# Verificamos que la URL efectiva sea la esperada.
if ! sub_url_eff="$(git -C "$DEST" config --get submodule.kernel-6.6.url)"; then
  sub_url_eff=""
fi
[ "$sub_url_eff" = "$SUB_URL" ] || die "URL del submódulo: $sub_url_eff != $SUB_URL"

sum="$(sha256sum "$DEST/build_kernel.sh" | cut -d' ' -f1)"
mkdir -p manifests
printf '%s  build_kernel.sh\n' "$sum" > manifests/a34-build_kernel.sha256

log "OK: $COMMIT / kernel-6.6 $SUB_COMMIT"
log "build_kernel.sh sha256 $sum"
