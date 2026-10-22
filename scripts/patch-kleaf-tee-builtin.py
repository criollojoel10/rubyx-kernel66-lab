#!/usr/bin/env python3
"""Deja la lista de modulos de Kleaf sin los .ko de TEEGRIS.

El TEE de ruby (Microtrust TEEI 400) se compila built-in, igual que en el
kernel stock de ruby: el GKI incluye el arbol de device modules con
`obj-y += ../$(DEVICE_MODULES_REL_DIR)/drivers/tee/`. Por tanto no existe
ningun .ko de TEE que recoger, pero la lista `mgk_64_device_modules` de
Kleaf todavia espera los .ko de TEEGRIS 510/515 y falla con
"Unable to find drivers/tee/teei/510/isee.ko".

Este script:
  - quita de las listas las entradas de TEEGRIS (isee.ko / isee-ffa.ko);
  - comenta las llamadas .remove()/.append() sobre esos nombres: si el
    elemento no esta en la lista, remove() aborta la carga del .bzl.

Uso: scripts/patch-kleaf-tee-builtin.py [raiz/del/arbol]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sources/a34x"
BZL = BASE / "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl"

if not BZL.exists():
    sys.exit(f"falta {BZL}; ejecuta make fetch")

text = BZL.read_text()
orig = text

# 1) entradas de lista de TEEGRIS
n_entries = 0
out = []
for line in text.splitlines(keepends=True):
    if re.match(r'^\s*"drivers/tee/teei/51[05]/isee(-ffa)?\.ko",\s*$', line):
        n_entries += 1
        out.append("# ruby: TEE built-in (Microtrust 400) -> " + line.strip() + "\n")
    else:
        out.append(line)
text = "".join(out)

# 2) remove()/append() sobre esos nombres: se comentan
n_calls = 0
out = []
for line in text.splitlines(keepends=True):
    if ("isee" in line) and re.search(r'\.(remove|append)\(', line) \
            and not line.lstrip().startswith("#"):
        n_calls += 1
        indent = line[:len(line) - len(line.lstrip())]
        out.append(f"{indent}# ruby: {line.strip()}\n")
    else:
        out.append(line)
text = "".join(out)

if text != orig:
    BZL.write_text(text)
    print(f"[kleaf] {n_entries} entradas de TEEGRIS quitadas, "
          f"{n_calls} remove/append comentados")
else:
    print("[kleaf] la lista ya estaba sin TEEGRIS")
