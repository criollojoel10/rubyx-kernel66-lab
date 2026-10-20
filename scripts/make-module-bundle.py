#!/usr/bin/env python3
"""Copia el cierre de módulos y genera modules.load en orden topológico.

    ./scripts/make-module-bundle.py <dir_todos_los_ko>
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "port/modules/closure"


def depends(path):
    r = subprocess.run(["modinfo", "-F", "depends", str(path)],
                       capture_output=True, text=True, check=False)
    return [x for x in r.stdout.strip().split(",") if x]


def main():
    if len(sys.argv) < 2:
        raise SystemExit("falta el directorio con los .ko")
    moddir = Path(sys.argv[1])
    closure = json.loads((ROOT / "port/modules/closure.json").read_text())["modules"]

    files = {}
    deps = {}
    for ko in moddir.rglob("*.ko"):
        files[ko.stem] = ko
        deps[ko.stem] = depends(ko)

    missing = [m for m in closure if m not in files]
    if missing:
        raise SystemExit(f"faltan en el árbol: {missing}")

    order = []
    seen = set()
    def visit(name):
        if name in seen:
            return
        seen.add(name)
        for d in deps.get(name, []):
            if d in files:
                visit(d)
        if name in closure:
            order.append(name)

    for m in closure:
        visit(m)

    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.ko"):
        f.unlink()
    for m in order:
        shutil.copy2(files[m], OUT / f"{m}.ko")
    (OUT / "modules.load").write_text("\n".join(f"{m}.ko" for m in order) + "\n")
    (OUT / "modules.order").write_text("\n".join(f"{m}.ko" for m in order) + "\n")
    print(f"{len(order)} módulos -> {OUT}")
    print("primeros:", order[:5])
    print("últimos:", order[-5:])


if __name__ == "__main__":
    main()
