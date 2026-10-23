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
    if re.search(r'teei/51[05]/isee', line) and re.search(r'\.(remove|append)\(', line) \
            and not line.lstrip().startswith("#"):
        n_calls += 1
        indent = line[:len(line) - len(line.lstrip())]
        out.append(f"{indent}# ruby: {line.strip()}\n")
    else:
        out.append(line)
text = "".join(out)

# 3) tee.ko (el core del TEE) tambien va dentro de la Image: al apagar
#    CONFIG_TEE en los device modules el .ko ya no existe y kleaf aborta con
#    "Unable to find drivers/tee/tee.ko". Vive en mgk_modules.bzl.
n_core = 0
for BZL_CORE in (BASE / "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_modules.bzl",):
    if not BZL_CORE.exists():
        continue
    text_core = BZL_CORE.read_text()
    out = []
    for line in text_core.splitlines(keepends=True):
        if re.match(r'^\s*"drivers/tee/tee\.ko",\s*$', line):
            n_core += 1
            out.append("# ruby: TEE built-in (Microtrust 400) -> "
                       + line.strip() + "\n")
        else:
            out.append(line)
    nuevo = "".join(out)
    if nuevo != text_core:
        BZL_CORE.write_text(nuevo)

# 4) tzdev.ko y tuihw*.ko dependen de TZDEV/TEEGRIS_TUI, apagados
#    (viven dentro del submenu de TEE). Se comentan sus .append() en
#    mgk_64.bzl para que kleaf no aborte con "Unable to find ... .ko".
n_tz = 0
BZL64 = BASE / "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl"
if BZL64.exists():
    text64 = BZL64.read_text()
    out = []
    for line in text64.splitlines(keepends=True):
        if (not line.lstrip().startswith("#")
                and "ruby: TEE off" not in line
                and ".append(" in line
                and any(m in line for m in ("tzdev/4/tzdev.ko",
                                            "tzdev/5/tzdev.ko",
                                            "tzdev/6/tzdev.ko",
                                            "tui/tuihw.ko",
                                            "tui/tuihw-inf.ko"))):
            n_tz += 1
            indent = line[:len(line) - len(line.lstrip())]
            out.append(f"{indent}pass  # ruby: TEE off, was: {line.strip()}\n")
        else:
            out.append(line)
    nuevo = "".join(out)
    if nuevo != text64:
        BZL64.write_text(nuevo)
print(f"[kleaf] {n_tz} append de tzdev/tuihw comentados")

if text != orig:
    BZL.write_text(text)
    print(f"[kleaf] {n_entries} entradas de TEEGRIS quitadas, "
          f"{n_calls} remove/append comentados")
else:
    print("[kleaf] la lista ya estaba sin TEEGRIS")
# 5) modulos que dependen de TEE/TZDEV/TEEGRIS y ya no se construyen:
#    teeperf.ko (mgk_64.bzl), mstdrv.ko (lego.bzl), tuihw*.ko
#    (samsung_product_modules.bzl). Se comentan para que kleaf no aborte con
#    "Unable to find ... .ko".
targets = {
    "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl": [
        "drivers/tee/teeperf/teeperf.ko",
    ],
    "kernel/kernel_device_modules-6.6/lego.bzl": [
        "drivers/mstdrv/mstdrv.ko",
    ],
    "kernel/kernel_device_modules-6.6/kernel/kleaf/samsung_product_modules.bzl": [
        "drivers/tee/tui/tuihw.ko",
        "drivers/tee/tui/tuihw-inf.ko",
    ],
}
n_static = 0
for rel, mods in targets.items():
    path = BASE / rel
    if not path.exists():
        continue
    lines = path.read_text().splitlines(keepends=True)
    out = []
    for line in lines:
        if (not line.lstrip().startswith("#")
                and "_ruby_remove(" not in line
                and any(m in line for m in mods)):
            n_static += 1
            indent = line[:len(line) - len(line.lstrip())]
            out.append(f"{indent}# ruby: TEE off -> {line.strip()}\n")
        else:
            out.append(line)
    path.write_text("".join(out))
print(f"[kleaf] {n_static} entradas estaticas comentadas (teeperf/mstdrv/tuihw)")
# 5b) _ruby_add(... isee.ko) anade isee.ko como modulo, pero va built-in.
#     Se cambia por _ruby_remove para que no se espere el .ko.
BZL64 = BASE / "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl"
if BZL64.exists():
    text64 = BZL64.read_text()
    old_line = '_ruby_add(mgk_64_device_modules, "drivers/tee/teei/400/isee.ko")'
    new_line = '_ruby_remove(mgk_64_device_modules, "drivers/tee/teei/400/isee.ko")  # ruby: built-in'
    if old_line in text64:
        text64 = text64.replace(old_line, new_line, 1)
        BZL64.write_text(text64)
        print("[kleaf] _ruby_add(isee.ko) -> _ruby_remove")

# 6) red de seguridad: aunque los .append() esten comentados, si tzdev.ko o
#    tuihw*.ko quedan en la lista (por cache de bazel o por otra fuente) se
#    eliminan aqui de forma segura (guardado por 'in').
BZL64 = BASE / "kernel/kernel_device_modules-6.6/kernel/kleaf/mgk_64.bzl"
if BZL64.exists():
    text64 = BZL64.read_text()
    marker = "\n# ruby: red de seguridad"
    idx = text64.find(marker)
    if idx != -1:
        # reescribir siempre el bloque: garantiza idempotencia aunque el paso 5
        # haya tocado alguna linea del guard anterior.
        text64 = text64[:idx].rstrip() + "\n"
    guard = '\n# ruby: red de seguridad - eliminar tzdev/tuihw si quedaron en la lista\n'
    for mod in ("drivers/tee/tzdev/4/tzdev.ko", "drivers/tee/tzdev/5/tzdev.ko",
                "drivers/tee/tzdev/6/tzdev.ko",
                "drivers/misc/mediatek/tui/tuihw.ko",
                "drivers/misc/mediatek/tui/tuihw-inf.ko",
                "drivers/tee/teeperf/teeperf.ko",
                "drivers/mstdrv/mstdrv.ko"):
        # Starlark no permite 'if' a nivel superior: usar el helper existente.
        guard += (f'_ruby_remove(mgk_64_device_modules, "{mod}")'
                  f'  # ruby: sin modulo TEE\n')
    text64 = text64.rstrip() + "\n" + guard
    BZL64.write_text(text64)
    print("[kleaf] red de seguridad reescrita en mgk_64.bzl")
print(f"[kleaf] {n_core} entradas de drivers/tee/tee.ko quitadas, "
      f"{n_tz} append de tzdev/tuihw comentados")
