#!/usr/bin/env python3
"""Audita el piloto clk/pinctrl de port/clk y port/pinctrl contra el GKI."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
A34 = ROOT / "sources/a34x"
GKI = A34 / "kernel-6.6"
DEV = A34 / "kernel/kernel_device_modules-6.6"
OUT = ROOT / "port/summary.json"

INCLUDE = re.compile(r'^\s*#\s*include\s+[<"]([^>"]+)[>"]', re.M)
SHARED = [
    "drivers/clk/mediatek/clk-mtk.h",
    "drivers/clk/mediatek/clk-gate.h",
    "drivers/clk/mediatek/clk-mux.h",
    "drivers/pinctrl/mediatek/pinctrl-paris.h",
]


def roots():
    return [
        GKI / "include", GKI / "arch/arm64/include",
        GKI / "drivers/clk/mediatek", GKI / "drivers/pinctrl/mediatek",
        DEV / "include", DEV / "arch/arm64/include",
        DEV / "drivers/clk/mediatek", DEV / "drivers/pinctrl/mediatek",
        DEV / "drivers/misc/mediatek/include",
    ]


def resolve(name, src, roots_list):
    for r in roots_list:
        if (r / name).is_file():
            return str(r.relative_to(A34))
    if (src.parent / name).is_file():
        return "local"
    return ""


def main():
    roots_list = roots()
    files = sorted(list((ROOT / "port/clk").glob("clk-mt6877*")) +
                   list((ROOT / "port/pinctrl").glob("pinctrl-mt6877*")))
    report = {"files": [], "shared_header_diff_lines": {}, "missing": {}}
    for f in files:
        text = f.read_text(errors="ignore")
        incs = {}
        for inc in INCLUDE.findall(text):
            where = resolve(inc, f, roots_list)
            incs[inc] = where
            if not where:
                report["missing"].setdefault(str(f.relative_to(ROOT)), []).append(inc)
        report["files"].append({
            "path": str(f.relative_to(ROOT)),
            "lines": len(text.splitlines()),
            "includes": incs,
        })

    for h in SHARED:
        a, b = GKI / h, DEV / h
        if a.is_file() and b.is_file():
            r = subprocess.run(["diff", "-u", str(a), str(b)],
                               capture_output=True, text=True, check=False)
            report["shared_header_diff_lines"][h] = len(
                [l for l in r.stdout.splitlines() if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))])
        else:
            report["shared_header_diff_lines"][h] = None

    OUT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "files": len(report["files"]),
        "missing": report["missing"],
        "shared_header_diff_lines": report["shared_header_diff_lines"],
    }, indent=2))


if __name__ == "__main__":
    main()
