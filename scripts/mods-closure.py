#!/usr/bin/env python3
"""Arma un juego de modulos para el arranque de ruby (B) a partir de un
conjunto que ya arranca y de los .ko de un build nuevo.

Motivo: mediatek-drm.ko y los paneles m16 solo valen si salen del MISMO
build (los CRCs de mtk_panel_ext_* cambian entre builds), y arrastran una
cadena de dependencias que hay que cargar en orden. Este script calcula el
cierre de dependencias con modinfo y escribe modules.load deps-first.

Uso:
  mods-closure.py --base /tmp/opencode/mods27 \
                  --mods /tmp/opencode/ci-<run>/mods \
                  --out  /tmp/opencode/mods29 \
                  --root mediatek-drm --root mtk_panel_ext \
                  --root mtk_disp_notify --root mtk_sync \
                  --root pwm-mtk-disp --exclude mtk_wdt
"""
import argparse
import pathlib
import shutil
import subprocess
import sys


def deps(path):
    r = subprocess.run(["modinfo", "-F", "depends", str(path)],
                       capture_output=True, text=True)
    if r.returncode:
        print(f"[closure] aviso: modinfo falla en {path}: "
              f"{r.stderr.strip()}", file=sys.stderr)
        return []
    return [d for d in r.stdout.strip().split(",") if d]


def index(root):
    idx = {}
    for p in pathlib.Path(root).rglob("*.ko"):
        if "depmod-root" in p.parts:
            continue
        idx.setdefault(p.stem, p)
    return idx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="juego que ya arranca")
    ap.add_argument("--mods", required=True, help="arbol del build nuevo")
    ap.add_argument("--out", required=True)
    ap.add_argument("--root", action="append", default=[])
    ap.add_argument("--exclude", action="append", default=[])
    a = ap.parse_args()

    have = index(a.mods)
    orden, seen, missing = [], set(), []

    def visit(name, padre=None):
        if name in seen:
            return
        seen.add(name)
        if name in a.exclude:
            print(f"[closure] excluido {name}")
            return
        if name not in have:
            missing.append((name, padre or "root"))
            return
        for d in deps(have[name]):
            visit(d, name)
        orden.append(name)

    if not a.root:
        sys.exit("hace falta al menos un --root")
    for r in a.root:
        visit(r)
    if missing:
        for n, p in missing:
            print(f"[closure] FALTA {n} (lo pide {p})", file=sys.stderr)
        return 1

    base = pathlib.Path(a.base)
    out = pathlib.Path(a.out)
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(base, out)

    nuevos = []
    for name in orden:
        ya = out / f"{name}.ko"
        if ya.exists():
            ya.unlink()
        shutil.copy2(have[name], ya)
        if name not in {p.stem for p in base.glob("*.ko")}:
            nuevos.append(name)

    viejos = [l.strip() for l in (base / "modules.load").read_text().splitlines()
              if l.strip() and not l.strip().startswith("#")]
    viejos = [m for m in viejos if (out / m).exists() and m not in a.exclude]

    # modules.load lleva el nombre del fichero CON extension: el loader del
    # ramdisk hace snprintf(".../%s", name) sin anadir ".ko".
    stems_viejos = [m[:-3] if m.endswith(".ko") else m for m in viejos]
    presentes = {p.stem for p in out.glob("*.ko")}
    todos = set(stems_viejos) | set(nuevos)

    # Orden final deps-first para la union (viejos + nuevos): un modulo nuevo
    # puede ser dependencia de uno viejo (clk-mt6877-pg antes de mtk-smi) y al
    # reves, asi que concatenar las dos listas no basta.
    final, visto = [], set()

    def emitir(name):
        if name in visto or name not in todos:
            return
        visto.add(name)
        for d in deps(out / f"{name}.ko"):
            emitir(d)
        final.append(f"{name}.ko")

    for name in stems_viejos + nuevos:
        emitir(name)
    for name in sorted(todos - visto):
        final.append(f"{name}.ko")

    (out / "modules.load").write_text("\n".join(final) + "\n")
    print(f"[closure] {len(orden)} modulos en el cierre, {len(nuevos)} nuevos: "
          f"{' '.join(n + '.ko' for n in nuevos)}")
    print(f"[closure] modules.load: {len(final)} lineas -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
