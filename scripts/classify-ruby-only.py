#!/usr/bin/env python3
"""Clasifica los compatibles ruby-only por driver real en A34 y en ruby 4.19.

    ./scripts/classify-ruby-only.py

Salida:
  inventories/classification/ruby-only.tsv
  inventories/classification/summary.json
"""
import json
import re
import subprocess
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIVE = ROOT / "dts/ruby-live.dts"
RUBY_ONLY = ROOT / "inventories/live-vs-a34/compatibles-ruby-only.txt"
A34 = ROOT / "sources/a34x"
A34_TREES = [A34 / "kernel/kernel_device_modules-6.6", A34 / "kernel-6.6"]
RUBY = ROOT / "sources/ruby-4.19"
OUT = ROOT / "inventories/classification"

QUOTED = re.compile(r'"([^"\n]{1,120})"')
NODE = re.compile(r'^\s*([A-Za-z0-9_@,.\-]+)\s*\{\s*$')
LABELED_NODE = re.compile(r'^\s*[A-Za-z0-9_\-]+\s*:\s*([A-Za-z0-9_@,.\-]+)\s*\{\s*$')


def parse_live(path: Path):
    """Devuelve compatible -> lista de paths de nodo."""
    result = defaultdict(list)
    stack = []
    pending = None
    buf = ""
    for raw in path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue

        if pending is not None:
            buf += " " + line
            if ";" in line:
                for s in QUOTED.findall(buf):
                    result[s].append(pending)
                pending = None
                buf = ""
            continue

        m = LABELED_NODE.match(raw) or NODE.match(raw)
        if m and not line.startswith("/ {"):
            name = m.group(1)
            stack.append(name)
            continue
        if line == "/ {":
            stack = []
            continue
        if line.startswith("};"):
            if stack:
                stack.pop()
            continue

        if line.startswith("compatible"):
            pending = "/" + "/".join(stack)
            buf = line
            if ";" in line:
                for s in QUOTED.findall(buf):
                    result[s].append(pending)
                pending = None
                buf = ""
    return result


def candidate_c_files(root: Path):
    r = subprocess.run(
        ["grep", "-rlE", "--include=*.c", "compatible|of_device_id|of_match", str(root)],
        capture_output=True, text=True, check=False)
    return [Path(x) for x in r.stdout.splitlines() if x]


def driver_index(root: Path, targets=None):
    idx = defaultdict(list)
    files = candidate_c_files(root)
    for f in files:
        try:
            text = f.read_text(errors="ignore")
        except OSError:
            continue
        for s in QUOTED.findall(text):
            if targets is None or s in targets:
                idx[s].append(str(f.relative_to(root)))
    return idx, len(files)


def variant(s: str) -> str:
    """mt6359p-rtc -> mt6359-rtc; mt6359p -> mt6359."""
    s = s.replace("_", "-")
    return re.sub(r"(mt\d{4})p(?=[-,]|$)", r"\1", s)


def main():
    targets = {l.strip() for l in RUBY_ONLY.read_text().splitlines() if l.strip()}
    live = parse_live(LIVE)
    OUT.mkdir(parents=True, exist_ok=True)

    all_targets = set(live) | targets
    a34_idx = defaultdict(list)
    a34_all = defaultdict(list)
    a34_files = 0
    for tree in A34_TREES:
        if tree.is_dir():
            idx, n = driver_index(tree, all_targets)
            allidx, _ = driver_index(tree, None)
            a34_files += n
            for k, v in idx.items():
                a34_idx[k].extend(f"{tree.name}/{p}" for p in v)
            for k, v in allidx.items():
                a34_all[k].extend(f"{tree.name}/{p}" for p in v)
    a34_norm = defaultdict(set)
    for k in a34_all:
        a34_norm[variant(k)].add(k)

    ruby_idx, ruby_files = driver_index(RUBY, all_targets)

    path_compat = defaultdict(set)
    for c, paths in live.items():
        for pth in paths:
            path_compat[pth].add(c)

    rows = []
    counts = Counter()
    for c in sorted(targets):
        paths = live.get(c, [])
        reserved = any("/reserved-memory" in pth for pth in paths)
        siblings = set()
        for pth in paths:
            siblings |= path_compat[pth]
        siblings.discard(c)
        in_a34 = bool(a34_idx.get(c))
        in_ruby = bool(ruby_idx.get(c))
        a34_alt = any(a34_idx.get(s) for s in siblings)
        ruby_alt = any(ruby_idx.get(s) for s in siblings)
        aliases = sorted(x for x in a34_norm.get(variant(c), set()) if x != c)
        if reserved:
            cat = "reserved-memory"
        elif in_a34:
            cat = "driver-in-a34"
        elif aliases:
            cat = "alias-a34"
        elif a34_alt:
            cat = "fallback-a34"
        elif in_ruby:
            cat = "port-driver"
        elif ruby_alt:
            cat = "fallback-ruby"
        else:
            cat = "dts-only"
        counts[cat] += 1
        alias_files = []
        for a in aliases:
            alias_files.extend(a34_all.get(a, []))
        rows.append((c, cat, ";".join(sorted(set(paths))),
                     ";".join(sorted(set(a34_idx.get(c, [])))),
                     ";".join(sorted(set(ruby_idx.get(c, [])))),
                     ";".join(aliases),
                     ";".join(sorted(set(alias_files)))))

    with (OUT / "ruby-only.tsv").open("w") as f:
        f.write("compatible\tcategory\tlive_paths\ta34_drivers\truby419_drivers\ta34_aliases\ta34_alias_files\n")
        for row in rows:
            f.write("\t".join(row) + "\n")

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "ruby_only": len(targets),
        "a34_c_files_scanned": a34_files,
        "ruby419_c_files_scanned": ruby_files,
        "categories": dict(counts),
        "port_drivers": [r[0] for r in rows if r[1] == "port-driver"],
        "fallback_a34": [r[0] for r in rows if r[1] == "fallback-a34"],
        "fallback_ruby": [r[0] for r in rows if r[1] == "fallback-ruby"],
        "alias_a34": [r[0] for r in rows if r[1] == "alias-a34"],
        "dts_only": [r[0] for r in rows if r[1] == "dts-only"],
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items()
                      if k not in ("port_drivers", "dts_only", "fallback_a34", "fallback_ruby", "alias_a34")}, indent=2))
    print("\nport-driver:")
    for c in summary["port_drivers"]:
        print(" ", c)
    print("\ndts-only:")
    for c in summary["dts_only"]:
        print(" ", c)


if __name__ == "__main__":
    main()
