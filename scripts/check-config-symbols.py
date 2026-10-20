#!/usr/bin/env python3
"""Comprueba que los CONFIG_* de un fragmento existan en los Kconfig del A34.

    ./scripts/check-config-symbols.py configs/ruby-6.6-minimal/ruby_earlycon.fragment
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
A34 = ROOT / "sources/a34x"
TREES = [A34 / "kernel-6.6", A34 / "kernel/kernel_device_modules-6.6"]

CONFIG = re.compile(r"^CONFIG_([A-Za-z0-9_]+)=", re.M)
KDEF = re.compile(r"^(?:menu)?config\s+([A-Za-z0-9_]+)\s*$", re.M)


def main():
    frag = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "configs/ruby-6.6-minimal/ruby_earlycon.fragment"
    wanted = CONFIG.findall(frag.read_text())
    known = set()
    for tree in TREES:
        for k in tree.rglob("Kconfig*"):
            if not k.is_file():
                continue
            try:
                known |= set(KDEF.findall(k.read_text(errors="ignore")))
            except OSError:
                pass

    missing = [s for s in wanted if s not in known]
    print(f"fragmento: {frag}")
    print(f"símbolos: {len(wanted)}  conocidos: {len(wanted) - len(missing)}  ausentes: {len(missing)}")
    for s in missing:
        print(f"  FALTA CONFIG_{s}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
