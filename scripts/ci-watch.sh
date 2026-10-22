#!/usr/bin/env bash
# Vigilante del CI del laboratorio: vuelca el estado de todos los runs a
# logs/ci-watch.log y avisa de los cambios de conclusion.
set -uo pipefail
export HOME=/root
cd /root/rubyx-kernel66-lab
mkdir -p logs
LOG="logs/ci-watch.log"

prev=""
while true; do
  cur=$(gh run list -R criollojoel10/rubyx-kernel66-lab --limit 12 \
        --json databaseId,status,conclusion,workflowName,createdAt \
        --jq '.[] | "\(.databaseId) \(.workflowName) \(.status) \(.conclusion // "-")"' \
        2>/dev/null | sort)
  {
    echo "=== $(date -u +%FT%TZ)"
    echo "$cur"
  } >> "$LOG"
  if [ "$cur" != "$prev" ]; then
    echo "--- cambio de estado $(date -u +%FT%TZ)" >> "$LOG"
    prev="$cur"
  fi
  sleep 120
done
