#!/usr/bin/env python3
"""Selecciona los módulos del A34 necesarios para el primer arranque de ruby.

    ./scripts/select-boot-modules.py [modules.sha256]

Salida: port/modules/boot-modules.list y summary.json
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = Path("/tmp/a34-dl4/a34-6.6.127-reference/a34-6.6.127/modules.sha256")
OUT = ROOT / "port/modules"

PATTERNS = [
    r"clk-mt6877.*\.ko",
    r"pinctrl-mt6877\.ko",
    r"mtk-pmic-wrap\.ko",
    r"mtk-spmi-pmic\.ko",
    r"mtk-spmi-tia-adc\.ko",
    r"spmi-mtk-mpu\.ko",
    r"rtc-mt6397\.ko",
    r"mt6359p.*\.ko",
    r"mt635x-auxadc\.ko",
    r"mt6577_auxadc\.ko",
    r"nvmem-mt635x-efuse\.ko",
    r"mtk-mmc.*\.ko",
    r"phy-mtk-ufs\.ko",
    r"mtk_iommu.*\.ko",
    r"iommu_.*\.ko",
    r"mtk_wdt\.ko",
    r"mtk-dvfsrc.*\.ko",
    r"mtk-mt6359\.ko",
    r"snd-soc-mt6359\.ko",
    r"mtk-pmic-keys\.ko",
]
RE = re.compile("|".join(f"(?:{p})" for p in PATTERNS))
SKIP = re.compile(r"(test|dbg|debug|kunit)", re.I)


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not src.is_file():
        raise SystemExit(f"falta {src}")
    names = []
    for line in src.read_text().splitlines():
        if not line.strip():
            continue
        name = Path(line.split()[-1]).name
        if RE.fullmatch(name) and not SKIP.search(name):
            names.append(name)
    names = sorted(set(names))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "boot-modules.list").write_text("\n".join(names) + "\n")
    (OUT / "summary.json").write_text(json.dumps({
        "source": str(src),
        "count": len(names),
        "modules": names,
    }, indent=2) + "\n")
    print(f"{len(names)} módulos -> {OUT / 'boot-modules.list'}")
    for n in names:
        print(" ", n)


if __name__ == "__main__":
    main()
