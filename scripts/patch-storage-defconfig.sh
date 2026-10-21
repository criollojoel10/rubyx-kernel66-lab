#!/usr/bin/env bash
# Desactiva las features Samsung del UFS en los defconfigs del A34 antes de compilar.
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(
  sources/a34x/kernel/kernel_device_modules-6.6/arch/arm64/configs/mediatek-bazel_defconfig
  sources/a34x/kernel/kernel_device_modules-6.6/arch/arm64/configs/mgk_64_k66_defconfig
  sources/a34x/kernel/kernel_device_modules-6.6/arch/arm64/configs/a34x_defconfig
)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "falta $f" >&2; exit 1; }
  python3 - "$f" <<'PY'
import re, sys
p=sys.argv[1]; s=open(p).read()
for sym in ("SEC_UFS_FEATURE","SCSI_UFS_MEDIATEK_DBG","MTK_BLOCK_IO_TRACER","BLK_SEC_COMMON","BLK_SEC_WB","BLK_SEC_STATS"):
    s=re.sub(rf'^CONFIG_{sym}=.*$', f'# CONFIG_{sym} is not set', s, flags=re.M)
open(p,'w').write(s)
PY
done
grep -q '^# CONFIG_SEC_UFS_FEATURE is not set' "${FILES[0]}"
grep -q '^# CONFIG_SEC_UFS_FEATURE is not set' "${FILES[1]}"

# El bloque Samsung blk-sec-* sigue compilándose por caché/config vieja;
# lo sacamos también del Makefile para que modpost no pida ufs_sec_*.
BLK=sources/a34x/kernel/kernel_device_modules-6.6/block/Makefile
[ -f "$BLK" ] || { echo "falta $BLK" >&2; exit 1; }
sed -i 's/^obj-$(CONFIG_BLK_SEC_COMMON)/#&/' "$BLK"
sed -i 's/^obj-$(CONFIG_BLK_SEC_WB)/#&/' "$BLK"
grep -q '^#obj-$(CONFIG_BLK_SEC_COMMON)' "$BLK"
grep -q '^#obj-$(CONFIG_BLK_SEC_WB)' "$BLK"
echo "defconfigs UFS: Samsung features desactivadas; blk-sec fuera"
