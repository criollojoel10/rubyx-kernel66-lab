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
for sym in ("SEC_UFS_FEATURE","SCSI_UFS_MEDIATEK_DBG","MTK_BLOCK_IO_TRACER","BLK_SEC_COMMON","BLK_SEC_WB","BLK_SEC_STATS","MQ_IOSCHED_SSG","MQ_IOSCHED_SSG_CGROUP","MQ_IOSCHED_SSG_WB"):
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
sed -i 's/^obj-$(CONFIG_MQ_IOSCHED_SSG)/#&/' "$BLK"
grep -q '^#obj-$(CONFIG_BLK_SEC_COMMON)' "$BLK"
grep -q '^#obj-$(CONFIG_BLK_SEC_WB)' "$BLK"
grep -q '^#obj-$(CONFIG_MQ_IOSCHED_SSG)' "$BLK"
HDR=sources/a34x/kernel/kernel_device_modules-6.6/block/blk-sec.h
[ -f "$HDR" ] || { echo "falta $HDR" >&2; exit 1; }
sed -i 's/^static struct gendisk \*blk_sec_internal_disk/static __attribute__((unused)) struct gendisk *blk_sec_internal_disk/' "$HDR"
grep -q '__attribute__((unused)) struct gendisk \*blk_sec_internal_disk' "$HDR"
# Listas de empaquetado: no intentar instalar módulos que ya no se compilan.
python3 - <<'PY'
from pathlib import Path
removals = {
 "sources/a34x/kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl": [
   '    "drivers/misc/mediatek/blocktag/blocktag.ko",',
   '    "drivers/ufs/ufs-mediatek-dbg.ko",',
 ],
 "sources/a34x/kernel/kernel_device_modules-6.6/kernel/kleaf/samsung_modules.bzl": [
   '    "block/blk-sec-common.ko",',
   '    "block/blk-sec-stats.ko",',
   '    "block/blk-sec-wb.ko",',
   '    "block/ssg.ko",',
 ],
}
for f, lines in removals.items():
    p=Path(f); s=p.read_text()
    for line in lines:
        if line not in s:
            raise SystemExit(f"falta {line} en {f}")
        s=s.replace(line+"\n", "")
    p.write_text(s)
PY
echo "defconfigs UFS: Samsung features desactivadas; blk-sec fuera; listas limpias"
