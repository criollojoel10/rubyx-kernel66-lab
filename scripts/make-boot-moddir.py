#!/usr/bin/env python3
"""Prepara el directorio de módulos que va dentro del ramdisk de ruby.

Extrae todos los .ko del artefacto `a34-all-modules.tar.zst`, corre `depmod`
y copia el cierre de dependencias de un conjunto de módulos raíz, en orden
topológico (dependencias primero) más un `modules.load`.

    ./scripts/make-boot-moddir.py --modules-tar artifacts/<run>/a34-all-modules.tar.zst \
        --out artifacts/ruby-mods [--roots port/modules/boot-modules.list]

Sin --roots usa la lista por defecto: los módulos del primer arranque del A34
más la cadena de almacenamiento (UFS), que en el GKI de ruby es modular.
"""
import argparse
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_ROOT_LIST = REPO / "port/modules/boot-modules.list"

# Módulos que el primer init necesita sí o sí: sin UFS no hay super.
EXTRA_ROOTS = [
    "ufs-mediatek-mod.ko",
    "phy-mtk-ufs.ko",
    "mtk_iommu.ko",
    "mtk-mmc-mod.ko",
    "rpmb-mtk.ko",
]


def extract_all(tar_path: Path, dest: Path) -> int:
    n = 0
    with tarfile.open(tar_path, "r:*") as tf:
        for member in tf:
            if not member.isfile() or not member.name.endswith(".ko"):
                continue
            target = dest / Path(member.name).name
            with tf.extractfile(member) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            n += 1
    return n


def kernel_release(modules_dir: Path) -> str:
    for ko in sorted(modules_dir.glob("*.ko")):
        out = subprocess.run(["modinfo", "-F", "vermagic", str(ko)],
                             capture_output=True, text=True)
        v = out.stdout.strip()
        if v:
            return v.split()[0]
    raise SystemExit("no pude leer el vermagic de ningún módulo")


def parse_dep(path: Path) -> tuple[list[str], dict[str, list[str]]]:
    order: list[str] = []
    deps: dict[str, list[str]] = {}
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        left, _, right = line.partition(":")
        name = Path(left.strip()).name
        order.append(name)
        deps[name] = [Path(d).name for d in right.split()]
    return order, deps


def closure(roots: list[str], deps: dict[str, list[str]]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []

    def visit(name: str, stack: tuple[str, ...] = ()) -> None:
        if name in seen or name in stack:
            return
        for d in deps.get(name, []):
            visit(d, stack + (name,))
        seen.add(name)
        result.append(name)

    for r in roots:
        visit(r)
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--modules-tar", required=True, type=Path)
    ap.add_argument("--out", default=REPO / "artifacts/ruby-mods", type=Path)
    ap.add_argument("--roots", default=DEFAULT_ROOT_LIST, type=Path)
    ap.add_argument("--keep-build", type=Path,
                    help="reutiliza/crea aquí el árbol lib/modules (depmod)")
    args = ap.parse_args()

    roots: list[str] = []
    if args.roots.is_file():
        roots += [l.strip() for l in args.roots.read_text().splitlines() if l.strip()]
    roots += [r for r in EXTRA_ROOTS if r not in roots]

    if args.keep_build:
        build = args.keep_build
        build.mkdir(parents=True, exist_ok=True)
        tmp_ctx = None
    else:
        tmp_ctx = tempfile.TemporaryDirectory(prefix="ruby-mods-")
        build = Path(tmp_ctx.name)

    try:
        if not any(build.glob("*.ko")):
            n = extract_all(args.modules_tar, build)
            print(f"extraídos {n} módulos de {args.modules_tar.name}")
        release = kernel_release(build)
        base = build.parent if not args.keep_build else build
        # depmod necesita lib/modules/<release>/; lo simulamos con -b.
        root = Path(tmp_ctx.name) if tmp_ctx else build / "depmod-root"
        libdir = root / "lib/modules" / release
        libdir.mkdir(parents=True, exist_ok=True)
        for ko in build.glob("*.ko"):
            target = libdir / ko.name
            if not target.exists():
                target.symlink_to(ko)
        subprocess.run(["depmod", "-b", str(root), release], check=False,
                       capture_output=True, text=True)
        dep_file = libdir / "modules.dep"
        if not dep_file.is_file():
            raise SystemExit(f"depmod no generó {dep_file}")
        order, deps = parse_dep(dep_file)
        missing = [r for r in roots if r not in deps]
        if missing:
            print("aviso: raíces sin .ko en el artefacto: " + " ".join(missing),
                  file=sys.stderr)
        # closure() devuelve orden topológico (dependencias primero).
        wanted = closure(roots, deps)

        out = args.out
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        copied = 0
        for name in wanted:
            src = build / name
            if src.is_file():
                dst = out / name
                shutil.copy2(src, dst)
                # Los .ko del build traen .debug_info: ~30 MB de 77 módulos.
                # Stripear deja el ramdisk en unos pocos MB.
                subprocess.run(["objcopy", "--strip-debug", str(dst)],
                               capture_output=True, text=True)
                copied += 1
        (out / "modules.load").write_text("".join(n + "\n" for n in wanted))
        print(f"{copied} módulos -> {out} (modules.load {len(wanted)} líneas)")
    finally:
        if tmp_ctx:
            tmp_ctx.cleanup()


if __name__ == "__main__":
    main()
