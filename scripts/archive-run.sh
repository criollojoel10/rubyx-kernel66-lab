#!/usr/bin/env bash
# Archiva en laurel los artefactos de un run del CI.
#
# laurel (Mi A3) no compila: tiene 3.5 GiB de RAM y 1.9 GiB ya en uso, asi que
# un build del kernel lo mata. Su valor es el disco: 85 GiB libres en
# /dev/sda15, seis veces lo que queda en la SD de begonia y mucho mas que el
# disco local. Aqui se guardan los boot.img/.tar.zst de cada run para poder
# volver a un kernel anterior sin reconstruirlo.
#
# Uso: scripts/archive-run.sh <run-id>
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME=/root

RUN="${1:?falta el run id}"
LOCAL="artifacts/ci-$RUN"
REMOTE="/srv/ci-artifacts/$RUN"

echo "== 1/3 descarga del run $RUN"
gh run download "$RUN" -D "$LOCAL" --repo criollojoel10/rubyx-kernel66-lab

echo "== 2/3 envio a laurel ($REMOTE)"
ssh laurel "mkdir -p '$REMOTE'"
scp -q -r "$LOCAL/." "laurel:$REMOTE/"

echo "== 3/3 comprobacion"
ssh laurel "du -sh '$REMOTE'; df -h / | tail -n 1"
ls "$LOCAL"
