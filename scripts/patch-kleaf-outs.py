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


def patch_build_list(mods) -> int:
    """Anade los .ko a `mtk_device_modules`, la lista que Kleaf COMPILA.

    Sin estar aqui, el modulo no se construye aunque el Kconfig lo deje =m y
    aunque figure en los outs. El ancla es la entrada de mtk_panel_ext.ko
    (los paneles viven al lado en el arbol), asi que el parche es estable
    frente a cambios en el resto de la lista.
    """
    text = BZL_MODS.read_text()
    ancla = '    "drivers/gpu/drm/mediatek/mediatek_v2/mtk_panel_ext.ko",\n'
    if ancla not in text:
        if all(f'"{m}"' in text for m in mods):
            return 0
        sys.exit(f"no encuentro el ancla mtk_panel_ext.ko en {BZL_MODS}; "
                 "no toco nada")
    nuevos = [m for m in mods if f'"{m}"' not in text.split(ancla, 1)[1][:4000]]
    if not nuevos:
        print("[kleaf] mtk_device_modules ya contiene los modulos")
        return 0
    cuerpo = "".join(f'    "{m}",\n' for m in nuevos)
    BZL_MODS.write_text(text.replace(ancla, ancla + cuerpo, 1))
    return len(nuevos)


def patch_device_modules(mods) -> int:
    """Saca los .ko del arbol de device modules de mgk_64_module_outs.

    `mgk_64_module_outs` se funde en `mgk_64_common_*`, que es el `module_outs`
    del kernel_build del ACK (`kernel-6.6`): Kleaf los busca en el staging de
    ESA compilacion. Un .ko del arbol de device modules (los paneles, por
    ejemplo) nunca sale de ahi, asi que declararlo alli rompe el build con
    "Unable to find drivers/gpu/drm/panel/panel-m16-...ko".

    Los modulos del arbol de device modules solo van en `mtk_device_modules`
    (ver patch_build_list): eso alimenta `kernel_module(outs = ...)`, que es
    quien los compila de verdad. Aqui solo se limpia lo que versiones
    anteriores del script metieron por error.
    """
    text = BZL_MODS.read_text()
    m = re.search(r"^mgk_64_module_outs = (\[[^\]]*\])", text, re.M)
    if not m:
        print("aviso: no se encontro mgk_64_module_outs", file=sys.stderr)
        return 0
    cuerpo = m.group(1)
    quitados = 0
    for mod in mods:
        nuevo = re.sub(rf'^\s*"{re.escape(mod)}",?\n', '', cuerpo, flags=re.M)
        if nuevo != cuerpo:
            cuerpo = nuevo
            quitados += 1
    if quitados:
        BZL_MODS.write_text(text.replace(m.group(0),
                                         f"mgk_64_module_outs = {cuerpo}", 1))
    return quitados


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
        if not a.endswith(".ko"):
            sys.exit(f"'{a}' no es un .ko: no lo declaro (argumentos validos: "
                     "--dm, --gki y rutas que acaben en .ko)")
        (dm_mods if mode == "dm" else gki_mods).append(a)
    mods = dm_mods + gki_mods
    if not mods:
        print("uso: patch-kleaf-outs.py [--dm|--gki] <rutas .ko> [...]", file=sys.stderr)
        return 1

    n1 = patch_outs(gki_mods)
    n2 = patch_device_modules(dm_mods)
    n3 = patch_build_list(dm_mods)
    import py_compile
    for f in (BZL_OUTS, BZL_MODS):
        try:
            py_compile.compile(str(f), doraise=True)
        except py_compile.PyCompileError as e:
            sys.exit(f"[kleaf] {f.name} ya no compila: {e}")
    print(f"[kleaf] outs: +{n1} entradas | fuera de mgk_64_module_outs: "
          f"{n2} | compilados (mtk_device_modules): +{n3}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
