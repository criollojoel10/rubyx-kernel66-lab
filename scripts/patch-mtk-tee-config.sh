#!/usr/bin/env bash
# Ruby usa el TEE de Microtrust (TEEI 400), pero va BUILT-IN en la Image: lo
# enciende configs/ruby-6.6/gki-builtins.fragment y el port copia sus fuentes
# al arbol del GKI. El arbol de device modules no puede construir su propia
# copia: modpost aborta con "exported twice" (tee.ko redefine teedev_open,
# tee_client_*, tee_shm_*, ... que ya exporta el vmlinux).
#
# Por eso aqui se APAGA el TEE en los device modules, en sign.config (el
# ultimo fragmento del merge: lo que se ponga ahi gana), y se limpian los
# restos que lo encienden en el overlay de TEEGRIS y en el defconfig.
set -euo pipefail
cd "$(dirname "$0")/.."

DM="sources/a34x/kernel/kernel_device_modules-6.6"
O="$DM/kernel/configs/mt6877_teegris_5_overlay.config"
DEFCONFIG="$DM/arch/arm64/configs/mediatek-bazel_defconfig"
SIGN="$DM/kernel/configs/sign.config"
[ -f "$O" ] || { echo "falta $O; ejecuta make fetch" >&2; exit 1; }
[ -f "$SIGN" ] || { echo "falta $SIGN; ejecuta make fetch" >&2; exit 1; }

python3 - "$O" "$DEFCONFIG" "$SIGN" <<'PY'
import os
import sys

MARK = "# --- ruby: TEE built-in en la Image (no como modulo) ---"

# Simbolos del TEE que se apagan en el arbol de device modules.
N = [
    "CONFIG_TEE",
    "CONFIG_MICROTRUST_TEE_SUPPORT",
    "CONFIG_MICROTRUST_TZ_DRIVER",
    "CONFIG_MICROTRUST_DYNAMIC_CORE",
    "CONFIG_MICROTRUST_VFS_DRIVER",
    "CONFIG_MICROTRUST_FP_DRIVER",
    "CONFIG_MICROTRUST_KEYMASTER_DRIVER",
]
KEYS = set(N)


def key_of(line):
    s = line.strip()
    if s.startswith("# ") and s.endswith(" is not set"):
        return s[2:-len(" is not set")].strip()
    return s.split("=")[0].strip()


def clean(path):
    """Quita todo lo que encienda o apague los simbolos del TEE."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    out, skip = [], False
    for line in lines:
        if line.strip() == MARK:
            skip = True
            continue
        if skip:
            if key_of(line) in KEYS:
                continue
            skip = False
        if key_of(line) in KEYS:
            continue
        out.append(line)
    return out


def write(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip("\n") + "\n")


# 1) overlay de TEEGRIS y defconfig: fuera todo lo que encienda el TEE
for path in (sys.argv[1], sys.argv[2]):
    if os.path.exists(path):
        write(path, clean(path))
        print("[tee] TEE limpio en", os.path.basename(path))

# 2) sign.config: ultimo del merge, aqui se apaga de forma definitiva
lines = clean(sys.argv[3])
lines += [MARK] + [k + "=n" for k in N]
write(sys.argv[3], lines)
print("[tee] TEE apagado en sign.config (va built-in en la Image)")
PY

grep -E 'MICROTRUST|TEEGRIS|^CONFIG_TEE' "$O" || true

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

grep -n 'tzdev' "$GZ" || true

# ---------------------------------------------------------------------------
# Segundo sitio con el mismo problema: el subsistema "trusted_mem" de MTK
# (drivers/misc/mediatek/trusted_mem) incluye tambien "tee_client_api.h" y
# usa los tipos TEEC_* sin "struct" (typedef de TEEGRIS). Con Microtrust
# habilitado su Makefile anade el include path de teei, que gana y rompe la
# compilacion. Se anade tambien el path de TEEGRIS por delante.
# ---------------------------------------------------------------------------
TM="sources/a34x/kernel/kernel_device_modules-6.6/drivers/misc/mediatek/trusted_mem/Makefile"
[ -f "$TM" ] || { echo "falta $TM; ejecuta make fetch" >&2; exit 1; }

python3 - "$TM" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

old = """ifneq ($(filter y m,$(CONFIG_MICROTRUST_TEE_SUPPORT)),)
ccflags-y += -I$(DEVICE_MODULES_PATH)/drivers/tee/teei/$(CONFIG_MICROTRUST_TEE_VERSION)/common/include
"""
new = """ifneq ($(filter y m,$(CONFIG_MICROTRUST_TEE_SUPPORT)),)
# ruby: el codigo de trusted_mem usa los tipos TEEC_* de TEEGRIS (typedef).
# El include path de TEEGRIS debe ir antes que el de teei.
ccflags-y += -I$(DEVICE_MODULES_PATH)/drivers/tee/tzdev/$(CONFIG_TEEGRIS_VERSION)/include/tzdev
ccflags-y += -I$(DEVICE_MODULES_PATH)/drivers/tee/teei/$(CONFIG_MICROTRUST_TEE_VERSION)/common/include
"""

if "# ruby: el codigo de trusted_mem" in text:
    print("[tee] trusted_mem ya tiene el path de TEEGRIS")
elif old in text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(old, new, 1))
    print("[tee] path de TEEGRIS anadido a trusted_mem/Makefile")
else:
    sys.exit("no se encontro la rama de Microtrust en trusted_mem/Makefile")
PY

grep -n 'tzdev' "$TM" || true
