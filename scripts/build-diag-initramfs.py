#!/usr/bin/env python3
"""Construye el initramfs de diagnóstico (cpio newc + gzip)."""
import gzip
import stat
import sys
from pathlib import Path


def cpio_entry(name, data, mode, ino):
    encoded = name.encode() + b"\0"
    fields = [ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
    item = b"070701" + b"".join(f"{v:08x}".encode() for v in fields) + encoded
    item += b"\0" * ((-len(item)) % 4) + data
    return item + b"\0" * ((-len(data)) % 4)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("uso: build-diag-initramfs.py <init> <moddir> <out.cpio.gz>")
    init = Path(sys.argv[1])
    moddir = Path(sys.argv[2])
    out = Path(sys.argv[3])
    if not init.is_file():
        raise SystemExit(f"falta {init}")

    payload = b""
    ino = 1
    for d in ["dev", "proc", "sys", "lib", "lib/modules", "tmp"]:
        payload += cpio_entry(d, b"", stat.S_IFDIR | 0o755, ino)
        ino += 1
    payload += cpio_entry("init", init.read_bytes(), stat.S_IFREG | 0o700, ino)
    ino += 1
    for ko in sorted(moddir.glob("*.ko")):
        payload += cpio_entry(f"lib/modules/{ko.name}", ko.read_bytes(),
                              stat.S_IFREG | 0o644, ino)
        ino += 1
    load = moddir / "modules.load"
    payload += cpio_entry("lib/modules/modules.load", load.read_bytes(),
                          stat.S_IFREG | 0o644, ino)
    ino += 1
    payload += cpio_entry("TRAILER!!!", b"", 0, ino)

    out.write_bytes(gzip.compress(payload, mtime=0, compresslevel=9))
    print(f"{out} ({out.stat().st_size} bytes, {len(list(moddir.glob('*.ko')))} módulos)")


if __name__ == "__main__":
    main()
