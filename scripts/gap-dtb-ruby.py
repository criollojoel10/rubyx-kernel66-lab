#!/usr/bin/env python3
"""Inventario de drivers: que nodos del DTB de ruby se quedan sin soporte.

Compara los `compatible` del Device Tree de ruby (base 6.6 + dtbo) con los
que matchea el arbol 6.6 que compilamos (GKI de MTK 6.6.127 + device modules
+ los ports de ruby) y lista los que no tienen driver.

Uso: scripts/gap-dtb-ruby.py [--detalle]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DTS = [
    Path("/root/ruby-gki/extracted/dts/mt6877.dts"),
    Path("/root/ruby-gki/extracted/dts/ruby-dtbo.dts"),
]
ARBOLES = [
    ROOT / "sources/a34x/kernel-6.6",                      # GKI
    ROOT / "sources/a34x/kernel/kernel_device_modules-6.6",  # device modules
    ROOT / "port",                                          # ports de ruby
]

# compatibles que no son de ruby o que no hacen falta
IGNORAR = {
    "simple-bus", "fixed-clock", "simple-mfd", "syscon", "arm,pl430",
    "mediatek,mt6877-mmsys", "mediatek,smi_common", "arm,smmu-v3",
}


def compatibles_dtb() -> dict[str, str]:
    """compatible -> fichero donde aparece (la primera coincidencia)."""
    out: dict[str, str] = {}
    for f in DTS:
        if not f.exists():
            continue
        for m in re.finditer(r'compatible\s*=\s*"([^"]+)"', f.read_text(errors="ignore")):
            for c in m.group(1).split(","):
                c = c.strip()
                if c and c not in out:
                    out[c] = f.name
    return out


def drivers_del_arbol() -> set[str]:
    """compatible ->True de todo lo que matchea el arbol compilado."""
    found: set[str] = set()
    for tree in ARBOLES:
        if not tree.exists():
            continue
        # .compatible = "..."  (tablas of_device_id)
        r = subprocess.run(
            ["grep", "-rhoE", r'\.compatible\s*=\s*"[^"]+"', str(tree),
             "--include=*.c", "--include=*.h"],
            capture_output=True, text=True)
        for m in re.findall(r'"([^"]+)"', r.stdout):
            for c in m.split(","):
                c = c.strip()
                if c:
                    found.add(c)
    return found


def main() -> int:
    detalle = "--detalle" in sys.argv
    dtb = compatibles_dtb()
    drivers = drivers_del_arbol()

    # los compatibles compuestos: si uno coincide, vale
    sin = []
    for c, origen in sorted(dtb.items()):
        if c in IGNORAR:
            continue
        if c in drivers:
            continue
        sin.append((c, origen))

    print(f"compatibles en el DTB de ruby : {len(dtb)}")
    print(f"matcheados por el arbol 6.6   : {len(dtb) - len(sin) - len([c for c in dtb if c in IGNORAR])}")
    print(f"sin driver                    : {len(sin)}")
    print()
    for c, origen in sin:
        print(f"  {c:<52} ({origen})")

    if detalle:
        print()
        print("--- compatibles que SI tienen driver (muestra) ---")
        n = 0
        for c in sorted(dtb):
            if c in drivers and c not in IGNORAR:
                print(f"  OK {c}")
                n += 1
                if n > 40:
                    break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
