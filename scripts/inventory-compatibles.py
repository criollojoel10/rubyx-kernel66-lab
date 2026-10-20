#!/usr/bin/env python3
"""Inventario de `compatible` entre el árbol 4.19 de ruby y el BSP 6.6 del A34.

    ./scripts/inventory-compatibles.py [--ruby DIR] [--a34 DIR] [--out DIR]

Genera:
  inventories/compatibles-ruby.txt
  inventories/compatibles-a34.txt
  inventories/compatibles-common.txt
  inventories/compatibles-ruby-only.txt
  inventories/compatibles-a34-only.txt
  inventories/compatibles.tsv
  inventories/summary.json
"""
import argparse
import json
import re
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# compatible = "a,b", "c";
COMPAT_RE = re.compile(r'compatible\s*=\s*((?:"[^"]+"\s*,?\s*)+);', re.S)
STR_RE = re.compile(r'"([^"]+)"')


def git_head(path: Path):
    cur = path
    while True:
        if (cur / ".git").exists():
            r = subprocess.run(["git", "-C", str(cur), "rev-parse", "HEAD"],
                               capture_output=True, text=True, check=False)
            return r.stdout.strip() or None
        if cur.parent == cur:
            return None
        cur = cur.parent


def collect(tree: Path, pattern: str = ""):
    values = set()
    files = 0
    paths = [tree] if tree.is_file() else [p for p in tree.rglob("*") if p.is_file()]
    for path in paths:
        if not path.is_file():
            continue
        if path.suffix not in (".dts", ".dtsi"):
            continue
        if pattern:
            rel = str(path.relative_to(tree)) if tree.is_dir() else path.name
            if not re.search(pattern, rel):
                continue
        files += 1
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        for m in COMPAT_RE.finditer(text):
            for s in STR_RE.findall(m.group(1)):
                values.add(s.strip())
    return values, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ruby", default=str(ROOT / "sources/ruby-4.19"))
    ap.add_argument("--a34", default=str(ROOT / "sources/a34x/kernel/kernel_device_modules-6.6"))
    ap.add_argument("--out", default=str(ROOT / "inventories"))
    ap.add_argument("--filter-ruby", default="")
    ap.add_argument("--filter-a34", default="")
    args = ap.parse_args()

    ruby = Path(args.ruby)
    a34 = Path(args.a34)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    if not ruby.exists():
        raise SystemExit(f"falta {ruby} (clona RubyxLabs 4.19)")
    if not a34.exists():
        raise SystemExit(f"falta {a34} (fetch A34)")

    rset, rfiles = collect(ruby, args.filter_ruby)
    aset, afiles = collect(a34, args.filter_a34)

    common = rset & aset
    ronly = rset - aset
    aonly = aset - rset

    def dump(name, values):
        (out / name).write_text("\n".join(sorted(values)) + "\n")

    dump("compatibles-ruby.txt", rset)
    dump("compatibles-a34.txt", aset)
    dump("compatibles-common.txt", common)
    dump("compatibles-ruby-only.txt", ronly)
    dump("compatibles-a34-only.txt", aonly)

    with (out / "compatibles.tsv").open("w") as f:
        f.write("compatible\truby_4_19\ta34_6_6\n")
        for c in sorted(rset | aset):
            f.write(f"{c}\t{'yes' if c in rset else 'no'}\t{'yes' if c in aset else 'no'}\n")

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "ruby_tree": str(ruby),
        "ruby_head": git_head(ruby),
        "ruby_dts_files": rfiles,
        "ruby_compatibles": len(rset),
        "a34_tree": str(a34),
        "a34_head": git_head(a34),
        "a34_dts_files": afiles,
        "a34_compatibles": len(aset),
        "common": len(common),
        "ruby_only": len(ronly),
        "a34_only": len(aonly),
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
