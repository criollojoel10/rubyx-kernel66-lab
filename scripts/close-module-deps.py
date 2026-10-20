#!/usr/bin/env python3
"""Calcula el cierre de dependencias de los módulos de arranque.

    ./scripts/close-module-deps.py <dir_con_todos_los_ko> [lista_raiz]

Salida:
  port/modules/boot-modules-closure.list
  port/modules/closure.json
"""
import json
import subprocess
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LIST = ROOT / "port/modules/boot-modules.list"


def modinfo(field, path):
    r = subprocess.run(["modinfo", "-F", field, str(path)],
                       capture_output=True, text=True, check=False)
    return r.stdout.strip()


def main():
    if len(sys.argv) < 2:
        raise SystemExit("falta el directorio con los .ko")
    moddir = Path(sys.argv[1])
    rootlist = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_LIST
    if not moddir.is_dir():
        raise SystemExit(f"no existe {moddir}")

    files = {}
    depends = {}
    vermagic = {}
    for ko in moddir.rglob("*.ko"):
        name = ko.stem
        files[name] = ko
        d = modinfo("depends", ko)
        depends[name] = [x for x in d.split(",") if x]
        vermagic[name] = modinfo("vermagic", ko)

    roots = [l.strip() for l in rootlist.read_text().splitlines() if l.strip()]
    seen = set()
    missing = set()
    q = deque(roots)
    while q:
        name = q.popleft()
        if name in seen:
            continue
        if name not in files:
            missing.add(name)
            continue
        seen.add(name)
        for dep in depends.get(name, []):
            q.append(dep)

    ordered = sorted(seen)
    (ROOT / "port/modules/boot-modules-closure.list").write_text(
        "\n".join(ordered) + "\n")
    (ROOT / "port/modules/closure.json").write_text(json.dumps({
        "roots": len(roots),
        "total_modules": len(files),
        "closure": len(ordered),
        "missing_from_set": sorted(missing),
        "vermagic_unique": sorted(set(vermagic.values())),
        "modules": ordered,
    }, indent=2) + "\n")
    print(json.dumps({
        "roots": len(roots),
        "closure": len(ordered),
        "missing_from_set": sorted(missing),
        "vermagic_unique": sorted(set(vermagic.values())),
    }, indent=2))


if __name__ == "__main__":
    main()
