#!/usr/bin/env python3
"""Audita los drivers 4.19 que faltan en el A34.

Para cada `port-driver` de inventories/classification/ruby-only.tsv:
  - localiza el .c fuente en ruby 4.19;
  - comprueba que sus #include existan en los headers del A34;
  - intenta mapear el símbolo Kconfig del Makefile;
  - mide líneas y si el directorio existe en el A34.

Salida: inventories/api-audit/port-drivers.tsv y summary.json
"""
import csv
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TSV = ROOT / "inventories/classification/ruby-only.tsv"
RUBY = ROOT / "sources/ruby-4.19"
A34 = ROOT / "sources/a34x"
OUT = ROOT / "inventories/api-audit"

INCLUDE = re.compile(r'^\s*#\s*include\s+[<"]([^>"]+)[>"]', re.M)
OBJ = re.compile(r'obj-\$\(CONFIG_([A-Za-z0-9_]+)\)\s*\+?=\s*([^\s#]+)')


def include_roots():
    return [
        A34 / "kernel-6.6/include",
        A34 / "kernel-6.6/arch/arm64/include",
        A34 / "kernel/kernel_device_modules-6.6/include",
        A34 / "kernel/kernel_device_modules-6.6/arch/arm64/include",
    ]


def find_include(name, roots, source: Path):
    if name.startswith("generated/") or name in ("linux/version.h", "linux/utsrelease.h"):
        return "generated"
    for r in roots:
        if (r / name).is_file():
            return "yes"
    if (source.parent / name).is_file():
        return "relative"
    return "no"


def kconfig_symbol(source: Path):
    base = source.name[:-2] if source.name.endswith(".c") else source.name
    for d in (source.parent, source.parent.parent):
        mk = d / "Makefile"
        if not mk.is_file():
            continue
        text = mk.read_text(errors="ignore")
        for sym, obj in OBJ.findall(text):
            if obj.endswith(f"/{base}.o") or obj == f"{base}.o":
                return sym
        for sym, obj in OBJ.findall(text):
            if base in obj:
                return sym
    return ""


def a34_dir(source: Path):
    rel = source.relative_to(RUBY)
    for base in (A34 / "kernel/kernel_device_modules-6.6", A34 / "kernel-6.6"):
        if (base / rel.parent).is_dir():
            return "yes"
    return "no"


def subsystem(path: str):
    p = path.lower()
    for k, v in [
        ("gpu/drm/panel", "display/panel"), ("gpu/drm/mediatek", "display/mediatek"),
        ("misc/mediatek/leds", "display/backlight"), ("touchscreen", "touch"),
        ("fingerprint", "fingerprint"), ("power/supply", "charger"),
        ("input/misc", "haptics"), ("sound/soc", "audio"),
        ("mfd", "pmic"), ("rtc", "pmic"), ("nvmem", "pmic"), ("pmic", "pmic"),
        ("apusys", "apu"), ("devfreq", "dvfs"), ("i2c", "i2c"),
        ("media", "camera/video"), ("usb", "usb"), ("cpuidle", "cpuidle"),
        ("nfc", "nfc"), ("thermal", "thermal"), ("hw_random", "rng"),
        ("regulator", "regulator"),
    ]:
        if k in p:
            return v
    return "other"


def main():
    rows = list(csv.DictReader(TSV.open(), delimiter="\t"))
    roots = include_roots()
    OUT.mkdir(parents=True, exist_ok=True)

    out = []
    missing_counter = Counter()
    for r in rows:
        if r["category"] != "port-driver":
            continue
        paths = [x for x in r["ruby419_drivers"].split(";") if x]
        if not paths:
            continue
        src = RUBY / paths[0]
        if not src.is_file():
            continue
        text = src.read_text(errors="ignore")
        incs = []
        miss = []
        for inc in INCLUDE.findall(text):
            state = find_include(inc, roots, src)
            incs.append(f"{inc}:{state}")
            if state == "no":
                miss.append(inc)
                missing_counter[inc] += 1
        out.append({
            "compatible": r["compatible"],
            "subsystem": subsystem(paths[0]),
            "driver": paths[0],
            "loc": len(text.splitlines()),
            "kconfig": kconfig_symbol(src),
            "a34_dir": a34_dir(src),
            "missing_includes": len(miss),
            "missing": ";".join(miss),
        })

    out.sort(key=lambda x: (x["subsystem"], -x["missing_includes"], x["compatible"]))
    fields = ["compatible", "subsystem", "driver", "loc", "kconfig", "a34_dir",
              "missing_includes", "missing"]
    with (OUT / "port-drivers.tsv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
        w.writeheader()
        w.writerows(out)

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "drivers": len(out),
        "no_missing_includes": sum(1 for x in out if x["missing_includes"] == 0),
        "with_missing_includes": sum(1 for x in out if x["missing_includes"] > 0),
        "by_subsystem": dict(Counter(x["subsystem"] for x in out)),
        "top_missing_includes": missing_counter.most_common(30),
        "driver_dir_missing_in_a34": sum(1 for x in out if x["a34_dir"] == "no"),
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
