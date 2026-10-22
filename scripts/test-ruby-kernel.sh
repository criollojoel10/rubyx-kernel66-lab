#!/usr/bin/env bash
# Prueba completa del kernel 6.6 de ruby en el dispositivo:
#   1. descarga el artefacto de un run de CI
#   2. monta el boot.img (kernel + DTB de ruby + modulos)
#   3. lo flashea en el slot B con auto-retorno (tries=1)
#   4. verifica el arranque
#
# Uso: scripts/test-ruby-kernel.sh <run-id> [--no-flash]
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME=/root

RUN="${1:?falta el id del run}"
FLASH=1
[ "${2:-}" = "--no-flash" ] && FLASH=0

IMG="/tmp/ruby-6.6-$RUN.img"

echo "== 1/4 artefactos del run $RUN"
ART="artifacts/ci-$RUN"
if [ ! -d "$ART/a34-6.6.127" ]; then
  mkdir -p "$ART"
  NAME=$(gh run view -R criollojoel10/rubyx-kernel66-lab "$RUN" --json artifacts \
          --jq '.artifacts[] | select(.name|startswith("ruby-")) | select(.name|endswith("logs")|not) | .name' | head -1)
  [ -n "$NAME" ] || { echo "no hay artefacto 'ruby-*' en el run $RUN" >&2; exit 1; }
  gh run download -R criollojoel10/rubyx-kernel66-lab "$RUN" -n "$NAME" -D "$ART"
fi

echo "== 2/4 montando la imagen"
./scripts/build-ruby-boot.sh --artifacts "$ART/a34-6.6.127" --out "$IMG"
ls -l "$IMG"

if [ "$FLASH" = "0" ]; then
  echo "== sin flashear; imagen en $IMG"
  exit 0
fi

echo "== 3/4 flasheando en el slot B (auto-retorno)"
./scripts/run-slot-b-test.sh "$IMG"

echo "== 4/4 verificacion"
./scripts/verify-ruby.sh

echo "== fin. Logs en logs/"
