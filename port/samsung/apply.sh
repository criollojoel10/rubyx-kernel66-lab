#!/usr/bin/env bash
# Parches sobre los drivers Samsung de los device modules que ruby reutiliza
# para sus modulos de almacenamiento (ufs-mediatek-mod / mtk-mmc-mod piden
# sec_device_create).
#
# sec_ext.ko arranca con chipid_sysfs_init(), que llama a sysfs_create_svc_ap().
# Esa funcion asume que sec_debug_probe() ya corrio y dejo secdbg_pdev puesto,
# pero ruby no lleva el nodo "samsung,sec_debug" en su DTB (es Xiaomi, no
# Samsung), asi que secdbg_pdev es NULL y el primer acceso
# secdbg_pdev->dev.kobj.kset revienta el arranque:
#
#   Unable to handle kernel NULL pointer dereference at 0x30
#   pc : sysfs_create_svc_ap+0x18 [sec_ext]
#   lr : chipid_sysfs_init+0x54 [sec_ext]
#
# El fichero SVC_AP es informativo (service info). Se crea solo si el nodo de
# sec_debug existe.
#
# Uso: ./port/samsung/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  DM="$1/kernel/kernel_device_modules-6.6"
else
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

F="$DM/drivers/samsung/sec_chipid.c"
[ -f "$F" ] || { echo "falta $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import sys

p = sys.argv[1]
s = open(p).read()

if 'RUBY_SKIP_SVC_AP' in s:
    print("  (sec_chipid.c ya parcheado)")
    sys.exit(0)

old = '\tsysfs_create_svc_ap();\n'
new = (
    '\t/* RUBY_SKIP_SVC_AP: sysfs_create_svc_ap() da por hecho que\n'
    '\t * sec_debug_probe() ya corrio (secdbg_pdev != NULL). ruby no lleva\n'
    '\t * "samsung,sec_debug" en su DTB, asi que secdbg_pdev es NULL y el\n'
    '\t * acceso a secdbg_pdev->dev.kobj.kset mata el arranque al cargar\n'
    '\t * sec_ext.ko. El fichero SVC_AP es informativo.\n'
    '\t */\n'
    '\tif (secdbg_pdev)\n'
    '\t\tsysfs_create_svc_ap();\n'
)

if s.count(old) != 1:
    sys.exit("sec_chipid.c: no encuentro la llamada a sysfs_create_svc_ap()")

open(p, 'w').write(s.replace(old, new))
print("  sec_chipid.c: sysfs_create_svc_ap() solo si secdbg_pdev existe")
PY
