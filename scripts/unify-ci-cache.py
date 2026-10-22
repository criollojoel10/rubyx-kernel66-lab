#!/usr/bin/env python3
"""Unifica la clave de cache de Actions en todos los workflows (linea a linea).

Problema: cada workflow usaba su propio prefijo (ds-, core-, kabi-, mt-,
panel-...) y ademas metia ${{ github.sha }} en la clave primaria. Resultado:
"Cache not found for input keys" en todas las ejecuciones -> cada build era
un build en frio de Bazel (~39 min) y se acumulaban caches de 2 GB hasta
tocar el limite de 10 GB del repo (que provoca evictions).

Solucion: un unico prefijo compartido `a34-<hash del manifest>-` en
restore-keys, de modo que cualquier workflow restaure el cache mas reciente
del arbol A34 (mismo arbol, mismo clang, mismo stamping: el cache de acciones
de Bazel es valido para todos). La clave primaria conserva el sha para que
cada ejecucion guarde su propia instantanea.

Uso: scripts/unify-ci-cache.py [--check]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WFS = ROOT / ".github/workflows"

MANIFEST = "${{ hashFiles('manifests/a34-6.6.127.lock.json') }}"
SHARED = f"a34-{MANIFEST}-"

# prefijos historicos por workflow (mismo cache de Bazel, otro nombre)
# GitHub limita a 10 claves por cache (primaria + restore-keys), de ahi
# que listemos 7 legados como maximo.
LEGACY_PREFIXES = ("ds-", "core-", "kabi-", "mt-", "panel-", "fast-", "bazel-")


def process(path: Path, check: bool) -> bool:
    lines = path.read_text().splitlines(keepends=True)
    out = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]
        m = re.match(r"^(\s*)key:\s*(.+?)\s*$", line)
        if m and "hashFiles('manifests/a34-6.6.127.lock.json')" in m.group(2):
            indent, key = m.group(1), m.group(2)
            extra = ""
            for h in re.findall(r"hashFiles\('([^']+)'\)", key):
                if "manifests/a34-6.6.127.lock.json" not in h:
                    extra = f"-${{{{ hashFiles('{h}') }}}}"
            out.append(f"{indent}key: {SHARED.rstrip('-')}{extra}-${{{{ github.sha }}}}\n")
            changed = True
            i += 1
            continue

        m = re.match(r"^(\s*)restore-keys:\s*\|\s*$", line)
        if m:
            indent = m.group(1)
            out.append(line)
            i += 1
            # sustituye el bloque indentado por una sola linea con el prefijo
            while i < len(lines):
                nxt = lines[i]
                if nxt.strip() == "":
                    out.append(nxt)
                    i += 1
                    continue
                if not nxt.startswith(indent + " "):
                    break
                out.append(f"{indent}  {SHARED}\n")
                # prefijos historicos: permiten reutilizar los caches ya
                # guardados por cada workflow (mismo contenido: cache de
                # acciones de Bazel del arbol A34).
                for legacy in LEGACY_PREFIXES:
                    out.append(f"{indent}  {legacy}{MANIFEST}-\n")
                changed = True
                i += 1
                # salta el resto del bloque original
                while i < len(lines):
                    nxt = lines[i]
                    if nxt.strip() == "":
                        i += 1
                        continue
                    if nxt.startswith(indent + " "):
                        i += 1
                        continue
                    break
                break
            continue

        out.append(line)
        i += 1

    text = "".join(out)
    if not changed:
        return False
    if check:
        print(f"CAMBIARIA: {path.name}")
        return True
    path.write_text(text)
    print(f"actualizado: {path.name}")
    return True


def main() -> int:
    check = "--check" in sys.argv
    changed = 0
    for wf in sorted(WFS.glob("*.yml")):
        if process(wf, check):
            changed += 1
    if not changed:
        print("todos los workflows usan ya el prefijo compartido")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
