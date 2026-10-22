#!/usr/bin/env python3
"""Anade modulos nuevos a la lista `outs` de Kleaf (mgk_modules.bzl).

Kleaf exige que todo .ko que se compila este listado en el atributo `outs`
del target `mgk_64_k66_modules.user`; si no, el build acaba con:

    ERROR: The following kernel modules are built but not copied.
    Add these lines to the outs attribute of
    @//kernel_device_modules-6.6:mgk_64_k66_modules.user:
        "drivers/tee/teei/400/isee.ko",

Utilidad: ademas de dejar que se copien, listar el .ko hace que el build
FALLE si el modulo no llega a compilarse (bazel exige que exista el fichero
declarado en outs), es decir convierte la verificacion en parte del build.

Uso: scripts/patch-kleaf-outs.py <ruta_relativa_del.ko> [...]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BZL = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_modules.bzl"

LISTAS = ("mgk_module_eng_outs", "mgk_module_userdebug_outs", "mgk_module_user_outs")


def main() -> int:
    if not BZL.exists():
        print(f"falta {BZL}; ejecuta make fetch", file=sys.stderr)
        return 1
    mods = sys.argv[1:]
    if not mods:
        print("uso: patch-kleaf-outs.py <rutas .ko> [...]", file=sys.stderr)
        return 1

    text = BZL.read_text()
    cambiados = []
    for lista in LISTAS:
        m = re.search(rf"^{lista} = ([^\n]*)(\[[^\]]*\])", text, re.M)
        if not m:
            print(f"aviso: no se encontro la lista {lista}", file=sys.stderr)
            continue
        cabecera, cuerpo = m.group(1), m.group(2)
        nuevos = [f'    "{mod}",' for mod in mods if f'"{mod}"' not in cuerpo]
        if not nuevos:
            continue
        nuevo_cuerpo = cuerpo[:-1].rstrip() + "\n" + "\n".join(nuevos) + "\n]"
        text = text.replace(m.group(0), f"{lista} = {cabecera}{nuevo_cuerpo}", 1)
        cambiados.append((lista, len(nuevos)))

    BZL.write_text(text)
    for lista, n in cambiados:
        print(f"[kleaf] {lista}: +{n} modulos")
    if not cambiados:
        print("[kleaf] no habia nada que anadir")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
