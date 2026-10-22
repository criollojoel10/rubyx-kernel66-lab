#!/usr/bin/env python3
"""Declara los modulos nuevos de ruby en el build de Kleaf.

Dos listas tienen que tocarse:

1. `mgk_64_device_modules` (kernel/kleaf/mgk_64.bzl): la lista de modulos
   que el build **compila**. Sin estar aqui, el modulo no se construye
   aunque el Kconfig lo deje =m.
2. `mgk_module_{user,eng,userdebug}_outs` (kernel/kleaf/mgk_modules.bzl): los
   ficheros que el target copia. Si un .ko se compila y no esta aqui, Kleaf
   aborta con "The following kernel modules are built but not copied"; si
   esta aqui y no se compila, el build falla (que es justo lo que queremos
   para que un build verde signifique que el modulo existe).

Ademas, para Microtrust hay que cambiar el TEEGRIS 510 por el 400 (el TEE
real de ruby).

Uso: scripts/patch-kleaf-outs.py <ruta_relativa_del.ko> [...]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KLEAF = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/kernel/kleaf"
BZL_OUTS = KLEAF / "mgk_modules.bzl"
BZL_MODS = KLEAF / "mgk_64.bzl"

LISTAS = ("mgk_module_eng_outs", "mgk_module_userdebug_outs", "mgk_module_user_outs")

# modulos de TEEGRIS que hay que sustituir por el de Microtrust 400
TEE_REEMPLAZA = (
    "drivers/tee/teei/510/isee.ko",
    "drivers/tee/teei/510/isee-ffa.ko",
    "drivers/tee/teei/515/isee.ko",
)


def patch_outs(mods) -> int:
    text = BZL_OUTS.read_text()
    cambiados = 0
    for lista in LISTAS:
        m = re.search(rf"^{lista} = ([^\n]*)(\[[^\]]*\])", text, re.M)
        if not m:
            print(f"aviso: no se encontro la lista {lista}", file=sys.stderr)
            continue
        cabecera, cuerpo = m.group(1), m.group(2)
        # los modulos de TEEGRIS que sustituimos por el de Microtrust deben
        # salir de la lista de outs (si no, bazel busca un .ko que no existe)
        for viejo in TEE_REEMPLAZA:
            cuerpo = re.sub(rf'^\s*"{re.escape(viejo)}",?\n', '', cuerpo, flags=re.M)
        nuevos = [f'    "{mod}",' for mod in mods if f'"{mod}"' not in cuerpo]
        if not nuevos:
            continue
        nuevo_cuerpo = cuerpo[:-1].rstrip() + "\n" + "\n".join(nuevos) + "\n]"
        text = text.replace(m.group(0), f"{lista} = {cabecera}{nuevo_cuerpo}", 1)
        cambiados += len(nuevos)
    BZL_OUTS.write_text(text)
    return cambiados


def patch_device_modules(mods) -> int:
    """Los modulos que se compilan en el arbol de device modules.

    Los drivers de display/input/power de MTK viven en el GKI (en los device
    modules no hay Makefiles intermedios), asi que sus .ko solo se declaran
    en los outs; declararlos tambien en device_modules haria que el build
    los buscara donde no se construyen.
    """
    text = BZL_MODS.read_text()
    bloque = ["", "# --- ruby: modulos propios del proyecto ---",
              "def _ruby_add(mods, name):",
              "    if name not in mods:",
              "        mods.append(name)",
              "",
              "def _ruby_remove(mods, name):",
              "    if name in mods:",
              "        mods.remove(name)",
              ""]
    for viejo in TEE_REEMPLAZA:
        bloque.append(f'_ruby_remove(mgk_64_device_modules, "{viejo}")')
    for mod in mods:
        bloque.append(f'_ruby_add(mgk_64_device_modules, "{mod}")')
    bloque.append("")

    if "# --- ruby: modulos propios del proyecto ---" in text:
        print("[kleaf] la lista de device modules ya esta parcheada")
        return 0
    BZL_MODS.write_text(text.rstrip("\n") + "\n" + "\n".join(bloque))
    return len(mods)


def main() -> int:
    if not BZL_OUTS.exists() or not BZL_MODS.exists():
        print(f"falta {KLEAF}; ejecuta make fetch", file=sys.stderr)
        return 1
    argv = sys.argv[1:]
    dm_mods, gki_mods = [], []
    mode = "dm"
    for a in argv:
        if a == "--dm":
            mode = "dm"; continue
        if a == "--gki":
            mode = "gki"; continue
        (dm_mods if mode == "dm" else gki_mods).append(a)
    mods = dm_mods + gki_mods
    if not mods:
        print("uso: patch-kleaf-outs.py [--dm|--gki] <rutas .ko> [...]", file=sys.stderr)
        return 1

    n1 = patch_outs(mods)
    n2 = patch_device_modules(dm_mods)
    print(f"[kleaf] outs: +{n1} entradas | device_modules: +{n2} modulos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
