#!/usr/bin/env bash
# Build A34 6.6.127 + UFS upstream del GKI (sin Samsung).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/patch-storage-defconfig.sh
RUBY_OVERLAY=configs/ruby-6.6/storage.fragment ./scripts/build-a34-fast.sh
