#!/usr/bin/env bash
# Copia al GKI los drivers que necesita ruby y que en el arbol del A34 viven
# en los device modules:
#
#   drivers/tee/teei/400/            -> Microtrust TEEI 400 (el TEE de ruby)
#   drivers/gpu/drm/mediatek/mediatek_v2/ -> API de display v2 (la que usan el
#                                            panel m16 y el tactil FT3680 del
#                                            GKI, que son de Samsung)
#
# Se compilan built-in (=y) dentro del GKI, igual que en el kernel stock de
# ruby (que lleva todos los drivers de MTK built-in).
#
# Uso: ./port/mtk-drivers/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  GKI="$1/kernel-6.6"
  DM="$1/kernel/kernel_device_modules-6.6"
else
  GKI="sources/a34x/kernel-6.6"
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

# --- 1) TEEI 400 (Microtrust) ----------------------------------------------
if [ -d "$DM/drivers/tee/teei/400" ]; then
  rm -rf "$GKI/drivers/tee/teei"
  mkdir -p "$GKI/drivers/tee/teei"
  cp -a "$DM/drivers/tee/teei/400" "$GKI/drivers/tee/teei/400"
  # El Kconfig del TEEI vive en los device modules y nadie lo copiaba: sin el,
  # CONFIG_MICROTRUST_TEE_SUPPORT no existe en el arbol del GKI y olddefconfig
  # lo tira, asi que el TEE nunca entraba en la Image.
  cp "$DM/drivers/tee/teei/Kconfig" "$GKI/drivers/tee/teei/Kconfig"
  cp "$DM/drivers/tee/teei/Makefile.include" "$GKI/drivers/tee/teei/" 2>/dev/null || true
  cat > "$GKI/drivers/tee/teei/Makefile" <<'EOF'
# Microtrust TEEI: el TEE real de ruby (el A34 usa TEEGRIS de Samsung).
obj-$(CONFIG_MICROTRUST_TEE_SUPPORT) += $(subst ",,$(CONFIG_MICROTRUST_TEE_VERSION))/
EOF
  K="$GKI/drivers/tee/Makefile"
  python3 - "$K" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
# quita cualquier variante previa (la linea suelta de antes o el bloque)
lineas = [l for l in p.read_text().splitlines()
          if "MICROTRUST_TEE_SUPPORT" not in l
          and "obj-y += teei/" not in l
          and not l.strip().startswith(("# ruby:", "# pone asi)",
                                       "# copied'; el mismo arbol",
                                       "ifeq ($(CONFIG_MICROTRUST",
                                       "endif"))]
lineas += [
    "# ruby: el TEE va built-in. Con =m (el config de los device modules lo",
    "# pone asi) se compilaria isee.ko y Kleaf aborta con 'built but not",
    "# copied'; el mismo arbol se compila en los dos builds.",
    "ifeq ($(CONFIG_MICROTRUST_TEE_SUPPORT),y)",
    "obj-y += teei/",
    "endif",
]
p.write_text("\n".join(lineas) + "\n")
print("[mtk-drivers] teei enlazado solo con =y (built-in)")
PY

  # Sin el `source` en drivers/tee/Kconfig el simbolo que escribimos en
  # gki_defconfig no existe, y olddefconfig lo borra: el TEE no se compila.
  KC="$GKI/drivers/tee/Kconfig"
  if [ -f "$KC" ] && ! grep -q 'tee/teei/Kconfig' "$KC"; then
    python3 - "$KC" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
lineas = p.read_text().splitlines()
for i in range(len(lineas) - 1, -1, -1):
    if lineas[i].startswith("source "):
        lineas.insert(i + 1, 'source "drivers/tee/teei/Kconfig"')
        break
else:
    raise SystemExit("no hay ningun source en drivers/tee/Kconfig")
p.write_text("\n".join(lineas) + "\n")
print("[mtk-drivers] teei/Kconfig enganchado en drivers/tee/Kconfig")
PY
  fi

  # El arbol de device modules TAMBIEN tiene tee/teei: si el build superpone
  # esa copia sobre la del GKI, su Makefile lo volveria a enganchar con =m.
  DMT="$DM/drivers/tee/Makefile"
  if [ -f "$DMT" ]; then
    python3 - "$DMT" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
linea = "obj-$(CONFIG_MICROTRUST_TEE_SUPPORT) += teei/"
# anclado al principio de linea: no vuelve a tocar una ya comentada
nuevo, n = re.subn(r"(?m)^" + re.escape(linea) + r"$",
                   "# ruby: TEEI va built-in en el GKI, no como modulo\n# " + linea,
                   t, count=1)
if n:
    p.write_text(nuevo)
    print("[mtk-drivers] teei desenganchado del arbol de device modules")
PY
  fi
fi

# limpiar K para que no se arrastre al bloque del display
K=""

# --- 2) mediatek_v2 (display v2) -------------------------------------------
if [ -d "$DM/drivers/gpu/drm/mediatek/mediatek_v2" ]; then
  mkdir -p "$GKI/drivers/gpu/drm/mediatek"
  rm -rf "$GKI/drivers/gpu/drm/mediatek/mediatek_v2"
  cp -a "$DM/drivers/gpu/drm/mediatek/mediatek_v2" \
        "$GKI/drivers/gpu/drm/mediatek/mediatek_v2"
  M="$GKI/drivers/gpu/drm/mediatek/Makefile"
  grep -q 'mediatek_v2/' "$M" ||
    echo 'obj-$(CONFIG_DRM_MEDIATEK_V2) += mediatek_v2/' >> "$M"
  # El GKI de A34 usa la v1 (mi_disp) y no sourcea la v2: hay que engancharla.
  # kconfig resuelve los "source" relativos contra el cwd (la raiz del
  # package), no contra el directorio del Kconfig que lo contiene: por eso
  # el path es relativo y hace falta el symlink de abajo.
  # kconfig resuelve los "source" relativos contra el cwd (la raiz del
  # package), no contra el directorio del Kconfig que lo contiene: por eso
  # el path es relativo y hace falta el symlink de abajo.
  KC="$GKI/drivers/gpu/drm/mediatek/Kconfig"
  grep -q 'mediatek_v2/Kconfig' "$KC" ||
    echo 'source "mediatek_v2/Kconfig"' >> "$KC"
  # kconfig resuelve los "source" relativos contra el cwd (la raiz del
  # package), no contra el directorio del Kconfig que lo contiene: por eso
  # el GKI de A34 sourcea "mediatek_v2/Kconfig" y hace falta el symlink.
  ln -sfn drivers/gpu/drm/mediatek/mediatek_v2 "$GKI/mediatek_v2"
  ln -sfn drivers/gpu/drm/mediatek/mediatek_v2 "$DM/mediatek_v2"
  K="$GKI/drivers/gpu/drm/mediatek/Kconfig"
  echo "[mtk-drivers] mediatek_v2 copiada al GKI"
fi

# 3) cabeceros UAPI de MTK (los usa la mediatek_v2 y el panel m16) --------
# El GKI del A34 no los tiene; estan en los device modules.
for h in include/uapi/drm/mediatek_drm.h \
         include/linux/soc/mediatek/mtk-cmdq-ext.h \
         include/linux/mailbox/mtk-cmdq-mailbox-ext.h; do
  if [ -f "$DM/$h" ]; then
    mkdir -p "$GKI/$(dirname "$h")"
    cp -a "$DM/$h" "$GKI/$h"
    echo "[mtk-drivers] $h copiado al GKI"
  fi
done

# 3b) tipos de cmdq fuera del ifdef -------------------------------------
# mtk-cmdq-mailbox-ext.h declara cmdq_usage_cb / cmdq_mminfra_power /
# cmdq_mminfra_gce_cg dentro de "#if IS_ENABLED(CONFIG_MTK_CMDQ_MBOX_EXT)",
# pero luego los usa fuera (struct mbox_chan y prototipos). Ese CONFIG solo
# existe en los Kconfig de los device modules, asi que en el build GKI (y en
# el de modulos, que compila con la config del GKI) queda a 0 y el driver de
# touch no compila: "unknown type name 'cmdq_usage_cb'".
# Se suben los typedefs por encima del ifdef en ambas copias.
for CMDQ_H in "$GKI/include/linux/mailbox/mtk-cmdq-mailbox-ext.h" \
              "$DM/include/linux/mailbox/mtk-cmdq-mailbox-ext.h"; do
  [ -f "$CMDQ_H" ] || continue
  python3 - "$CMDQ_H" <<'PYEOF'
import sys
p = sys.argv[1]
text = open(p).read()
if "ruby: typedefs de cmdq" in text:
    sys.exit(0)
tipos = ("typedef bool (*cmdq_mminfra_power)(void);\n"
         "typedef bool (*cmdq_mminfra_gce_cg)(u32);\n"
         "\n"
         "typedef void (*cmdq_usage_cb)(u32);\n")
if tipos not in text:
    sys.exit(0)
text = text.replace(tipos, "", 1)
marca = "#if IS_ENABLED(CONFIG_MTK_CMDQ_MBOX_EXT)\n"
i = text.find(marca)
if i < 0:
    sys.exit(0)
text = (text[:i] + "/* ruby: typedefs de cmdq fuera del ifdef: el resto del\n"
        " * header los usa y CONFIG_MTK_CMDQ_MBOX_EXT solo existe en los\n"
        " * device modules, no en la config del GKI.\n"
        " */\n" + tipos + "\n" + text[i:])
open(p, "w").write(text)
PYEOF
  echo "[mtk-drivers] typedefs de cmdq liberados en $CMDQ_H"
done

# El header UAPI de MTK usa uint32_t/bool pero no incluye los tipos base:
# con clang (PCH) falla con "unknown type name 'uint32_t'". Se hace
# autosuficiente.
# se parchea tambien la copia de los device modules: el error salia al
# compilar la mediatek_v2 desde ahi
# El header UAPI de MTK usa uint32_t/bool sin resolverlos. En el arbol del
# kernel (include/uapi) eso lo da <linux/types.h>, pero los device modules se
# compilan como modulo externo (M=) contra las cabeceras INSTALADAS en
# usr/include, que son la version de userspace: ahi <linux/types.h> solo da
# __u32 y uint32_t/bool vienen de <stdint.h>/<stdbool.h>.
# Se resuelve como hace drm/drm.h: segun el contexto.
for UAPI in "$GKI/include/uapi/drm/mediatek_drm.h" \
            "$DM/include/uapi/drm/mediatek_drm.h"; do
if [ -f "$UAPI" ] && ! grep -q 'ruby: tipos de uapi' "$UAPI"; then
  python3 - "$UAPI" <<'PYEOF'
import sys
p = sys.argv[1]
text = open(p).read()
viejo = "#include <linux/types.h>\n#include <drm/drm.h>\n"
nuevo = ("/* ruby: tipos de uapi, como hacen las cabeceras del kernel.\n"
         " * Este header se compila ademas en su version SANITIZADA (la que\n"
         " * instala el kernel en usr/include para los modulos externos), y\n"
         " * ahi se quitan las ramas __KERNEL__ y los tipos de C que usa no\n"
         " * existen (vienen de stdint.h/stdbool.h, que el kernel no\n"
         " * exporta). Por eso se sustituyen por los tipos del kernel, que\n"
         " * si existen en los dos mundos y tienen el mismo ABI. */\n"
         "#include <linux/types.h>\n"
         "#include <drm/drm.h>\n")
if viejo not in text:
    # el header original de MTK no lleva linux/types.h
    viejo = "#include <drm/drm.h>\n"
    if viejo not in text:
        sys.exit("no encuentro el include de drm/drm.h")
text = text.replace(viejo, nuevo, 1)
# uint32_t/uint64_t/bool -> __u32/__u64/_Bool (mismo ABI, existe en ambos
# mundos: el kernel y la copia sanitizada de userspace)
import re as _re
text = _re.sub(r'\buint32_t\b', '__u32', text)
text = _re.sub(r'\buint64_t\b', '__u64', text)
text = _re.sub(r'\bbool\b', '_Bool', text)
open(p, "w").write(text)
PYEOF
  echo "[mtk-drivers] ${UAPI#sources/}: tipos de uapi resueltos"
fi
done

echo "[mtk-drivers] listo"
