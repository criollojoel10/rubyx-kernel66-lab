#!/usr/bin/env python3
"""Conecta el arbol de device modules con el kbuild del GKI.

En MGK, el GKI (kernel-6.6) se compila con el .config de los device modules
(kernel_device_modules-6.6). Los drivers del GKI salen de sus Makefiles; los
de los device modules solo se compilan si el GKI los incluye, y eso se hace
con `obj-y += ../$(DEVICE_MODULES_REL_DIR)/drivers/<dir>/` en el Makefile.ext
del GKI (asi lo hace el arbol publico de MTK para MT6877).

Que hace falta para ruby:

  drivers/tee/               -> Microtrust TEEI 400 (el TEE real de ruby)
  drivers/gpu/drm/mediatek/  -> mediatek_v2 (la API de panel que usa el
                                 panel m16 y el tactil FT3680)

Nota: al compilar la v2 hay que apagar la v1 del GKI (CONFIG_DRM_MEDIATEK=n)
para no duplicar simbolos (mtk_dsi_*, mtk_disp_*, ...).

Uso: scripts/patch-gki-mtk-drm.sh [raiz/del/arbol]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sources/a34x"
MODO = sys.argv[2] if len(sys.argv) > 2 else "full"   # "tee" o "full"
GKI = BASE / "kernel-6.6"
EXT = GKI / "Makefile.ext"

if not EXT.exists():
    sys.exit(f"falta {EXT}; ejecuta make fetch")

text = EXT.read_text()
# En el arbol del A34 los device modules viven en kernel/kernel_device_modules-6.6
# (en el arbol oficial de MTK serian un hermano del GKI, por eso MTK usa
# $(DEVICE_MODULES_REL_DIR) y aqui hay que poner la ruta a mano).
DM_REL = "../kernel/kernel_device_modules-6.6"

lines = [
    "# --- ruby: drivers del arbol de device modules ---",
    f"obj-y += {DM_REL}/drivers/tee/",
]
if MODO == "full":
    # mediatek_v2 (la API de panel que usan el m16 y el FT3680)
    lines.append(f"obj-y += {DM_REL}/drivers/gpu/drm/mediatek/")
lines.append("")
nuevo = "\n".join(lines)
if "ruby: drivers del arbol de device modules" in text:
    print("[gki] Makefile.ext ya parcheado")
elif MODO == "full" and "drivers/gpu/drm/mediatek/" not in text:
    EXT.write_text(text.rstrip("\n") + "\n\n" + "\n".join(lines))
    print("[gki] Makefile.ext parcheado (modo full)")
else:
    EXT.write_text(text.rstrip("\n") + "\n\n" + nuevo)
    print("[gki] Makefile.ext parcheado")
print(EXT.read_text()[-400:])
