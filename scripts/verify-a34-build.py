#!/usr/bin/env python3
"""Verifica el build de referencia del A34 6.6.127.

    ./scripts/verify-a34-build.py

No corrige nada: solo comprueba y devuelve exit 1 si algo no cuadra.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = json.loads((ROOT / "manifests/a34-6.6.127.lock.json").read_text())
ART = ROOT / "artifacts/a34-6.6.127"
SRC = ROOT / "sources/a34x"

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))


def run(*args, cwd=None):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd, check=False)


def main():
    ref = LOCK["reference"]
    sub = ref["submodules"][0]

    check("sources/a34x existe", SRC.is_dir(), str(SRC))
    if SRC.is_dir():
        head = run("git", "rev-parse", "HEAD", cwd=SRC).stdout.strip()
        check("commit del árbol", head == ref["commit"], f"{head} vs {ref['commit']}")
        tag = run("git", "describe", "--tags", "--exact-match", "HEAD", cwd=SRC).stdout.strip()
        check("tag exacto", tag == ref["tag"], f"{tag} vs {ref['tag']}")
        subdir = SRC / "kernel-6.6"
        if subdir.is_dir():
            shead = run("git", "rev-parse", "HEAD", cwd=subdir).stdout.strip()
            check("commit del submódulo", shead == sub["commit"], f"{shead} vs {sub['commit']}")
            mk = (subdir / "Makefile").read_text().splitlines()[:4]
            ver = "".join(x.split("=")[-1].strip() for x in mk if x.startswith(("VERSION", "PATCHLEVEL", "SUBLEVEL")))
            check("versión 6.6.127", ver == "66127", ver)
        else:
            check("submódulo kernel-6.6", False, "ausente")

    img = ART / "Image"
    check("Image existe", img.is_file() and img.stat().st_size > 1_000_000,
          f"{img.stat().st_size if img.is_file() else 0} bytes")
    if img.is_file():
        data = img.read_bytes()[:0x40]
        arm64 = len(data) >= 0x3C and data[0x38:0x3C] == b"ARM\x64"
        gzip = data[:2] == b"\x1f\x8b"
        check("Image arm64 o gzip", arm64 or gzip, "magic ARM64" if arm64 else ("gzip" if gzip else "desconocido"))

    cfg = ART / "config"
    if cfg.is_file() and cfg.stat().st_size:
        text = cfg.read_text(errors="ignore")
        check("config declara 6.6.127", "6.6.127" in text)
        check("config es arm64", "CONFIG_ARM64=y" in text)
    else:
        check("config extraído", False, "falta artifacts/.../config")

    sym = ART / "Module.symvers"
    if sym.is_file() and sym.stat().st_size:
        lines = [l for l in sym.read_text(errors="ignore").splitlines() if l.count("\t") >= 3]
        check("Module.symvers real", len(lines) > 100, f"{len(lines)} líneas")
    else:
        check("Module.symvers real", False, "ausente o vacío")

    ko = ART / "sample.ko"
    if ko.is_file():
        vm = run("modinfo", "-F", "vermagic", str(ko)).stdout.strip()
        check("vermagic de módulo", vm.startswith("6.6.127"), vm)
    else:
        check("módulo de muestra", False, "ausente")

    shas = ART / "sha256sums.txt"
    if shas.is_file() and shas.stat().st_size:
        r = subprocess.run(["sha256sum", "-c", "sha256sums.txt"], cwd=ART,
                           capture_output=True, text=True)
        check("hashes de artefactos", r.returncode == 0, r.stdout.strip().splitlines()[-1] if r.stdout else "")

    banned = ["|| true", "|| echo"]
    offenders = []
    for p in (ROOT / "scripts").glob("*"):
        if p.suffix not in (".sh", ".py"):
            continue
        txt = p.read_text(errors="ignore")
        for b in banned:
            if b in txt:
                offenders.append(f"{p.name}: {b}")
    check("scripts sin errores silenciados", not offenders, "; ".join(offenders))

    logs = sorted((ROOT / "logs").glob("a34-build-*.log"))
    check("log de build conservado", bool(logs), logs[-1].name if logs else "ninguno")

    failed = [n for n, ok, _ in results if not ok]
    print()
    print(f"{len(results) - len(failed)}/{len(results)} checks OK")
    if failed:
        print("FALLAN: " + ", ".join(failed))
        return 1
    print("A34_REFERENCE_BUILD=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
