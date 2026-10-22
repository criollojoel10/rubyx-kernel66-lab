#!/usr/bin/env bash
# Ruby necesita el TEE de Microtrust (TEEI), no TEEGRIS de Samsung.
# El overlay de A34 (mt6877_teegris_5_overlay.config) apaga Microtrust DESPUES
# de nuestro fragmento, asi que hay que editar ese overlay directamente.
set -euo pipefail
cd "$(dirname "$0")/.."

O="sources/a34x/kernel/kernel_device_modules-6.6/kernel/configs/mt6877_teegris_5_overlay.config"
[ -f "$O" ] || { echo "falta $O; ejecuta make fetch" >&2; exit 1; }

python3 - "$O" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

wanted = [
    "CONFIG_MICROTRUST_TEE_SUPPORT=m",
    'CONFIG_MICROTRUST_TEE_VERSION="400"',
    "CONFIG_MICROTRUST_TZ_DRIVER=y",
    "CONFIG_MICROTRUST_VFS_DRIVER=y",
    "CONFIG_MICROTRUST_FP_DRIVER=y",
    "CONFIG_MICROTRUST_KEYMASTER_DRIVER=y",
]

out = []
for line in lines:
    if line.strip() == "# CONFIG_MICROTRUST_TEE_SUPPORT is not set":
        continue
    if any(line.startswith(w.split("=")[0] + "=") for w in wanted):
        continue
    out.append(line)

out.append("# --- ruby: Microtrust TEEI 400 (TEE real de ruby) ---")
out.extend(wanted)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print("[tee] Microtrust 400 habilitado en", path)
PY

grep -E 'MICROTRUST|TEEGRIS' "$O"

# ---------------------------------------------------------------------------
# El driver geniezone de MTK usa la API GlobalPlatform de TEEGRIS
# (drivers/tee/tzdev/4/include/tzdev/tee_client_api.h). Al activar Microtrust,
# su Makefile incluye el Makefile.include de teei y ese header deja de estar
# en el path -> "use of undeclared identifier 'TEEC_UUID'".
# Solucion: anadir el path de TEEGRIS tambien en la rama de Microtrust.
# ---------------------------------------------------------------------------
GZ="sources/a34x/kernel/kernel_device_modules-6.6/drivers/misc/mediatek/geniezone/Makefile"
[ -f "$GZ" ] || { echo "falta $GZ; ejecuta make fetch" >&2; exit 1; }

python3 - "$GZ" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

old = """  else ifneq ($(filter y m, $(CONFIG_MICROTRUST_TEE_SUPPORT)),)
    include $(DEVICE_MODULES_PATH)/drivers/tee/teei/Makefile.include
"""
new = """  else ifneq ($(filter y m, $(CONFIG_MICROTRUST_TEE_SUPPORT)),)
    # ruby: geniezone usa la API GlobalPlatform de TEEGRIS (typedef TEEC_UUID).
    # El header de Microtrust solo declara "struct TEEC_UUID", asi que su
    # include path debe ir ANTES que el de teei para que gane el de TEEGRIS.
    ccflags-y += -I$(DEVICE_MODULES_PATH)/drivers/tee/tzdev/$(CONFIG_TEEGRIS_VERSION)/include/tzdev/
    include $(DEVICE_MODULES_PATH)/drivers/tee/teei/Makefile.include
"""

if "ruby: geniezone usa la API GlobalPlatform de TEEGRIS" in text:
    print("[tee] geniezone ya tiene el path de TEEGRIS")
elif old in text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(old, new, 1))
    print("[tee] path de TEEGRIS anadido a geniezone/Makefile")
else:
    sys.exit("no se encontro la rama de Microtrust en geniezone/Makefile")
PY

grep -n 'tzdev' "$GZ"
