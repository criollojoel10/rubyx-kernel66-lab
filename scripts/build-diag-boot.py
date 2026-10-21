#!/usr/bin/env python3
"""Construye un boot.img de diagnóstico conservando el layout del boot_b stock."""
import argparse
import struct
import subprocess
import tempfile
from pathlib import Path


def u32(b, off):
    return struct.unpack_from("<I", b, off)[0]


def u64(b, off):
    return struct.unpack_from("<Q", b, off)[0]


def parse_header_v2(image):
    if image[:8] != b"ANDROID!":
        raise SystemExit("no es un boot image Android")
    if u32(image, 40) != 2:
        raise SystemExit(f"header version {u32(image, 40)}; se esperaba 2")
    page = u32(image, 36)
    align = lambda n: (n + page - 1) // page * page
    ks, rs, ss = u32(image, 8), u32(image, 16), u32(image, 24)
    rec = u32(image, 1632)
    dtb_off = page + align(ks) + align(rs) + align(ss) + align(rec)
    ds = u32(image, 1648)
    return {
        "page": page,
        "kernel_addr": u32(image, 12),
        "ramdisk_addr": u32(image, 20),
        "tags_addr": u32(image, 32),
        "dtb_addr": u64(image, 1652),
        "dtb": image[dtb_off:dtb_off + ds],
        "cmdline": (image[64:576].split(b"\0")[0] + b" " +
                    image[608:1632].split(b"\0")[0]).decode().strip(),
        "os_version": u32(image, 44),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True, type=Path)
    ap.add_argument("--kernel", required=True, type=Path)
    ap.add_argument("--initramfs", required=True, type=Path)
    ap.add_argument("--dtb", type=Path)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()

    orig = args.original.read_bytes()
    h = parse_header_v2(orig)
    dtb = args.dtb.read_bytes() if args.dtb else h["dtb"]

    cmdline = "bootopt=64S3,32N2,64N2 androidboot.tee_type=2"

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        dtb_file = td / "dtb"
        dtb_file.write_bytes(dtb)
        raw_file = td / "raw.img"
        cmd = [
            "mkbootimg", "--header_version", "2", "--pagesize", str(h["page"]),
            "--base", "0", "--kernel_offset", hex(h["kernel_addr"]),
            "--ramdisk_offset", hex(h["ramdisk_addr"]),
            "--tags_offset", hex(h["tags_addr"]),
            "--dtb_offset", hex(h["dtb_addr"]),
            "--os_version", "17.0.0", "--os_patch_level", "2026-10",
            "--kernel", str(args.kernel), "--ramdisk", str(args.initramfs),
            "--dtb", str(dtb_file), "--cmdline", cmdline, "--output", str(raw_file),
        ]
        subprocess.run(cmd, check=True)
        raw = raw_file.read_bytes()

    # Conservar tamaño y AVB footer de la imagen original.
    footer = struct.unpack(">4sIIQQQ", orig[-64:-28])
    image = bytearray(len(orig))
    if footer[0] == b"AVBf":
        orig_size, vbmeta_offset, vbmeta_size = footer[3], footer[4], footer[5]
        if not len(raw) < orig_size <= vbmeta_offset:
            raise SystemExit("el payload no cabe antes del vbmeta original")
        image[:len(raw)] = raw
        image[vbmeta_offset:vbmeta_offset + vbmeta_size] = orig[vbmeta_offset:vbmeta_offset + vbmeta_size]
        image[-64:] = orig[-64:]
        print(f"AVB footer conservado (vbmeta {vbmeta_offset}+{vbmeta_size})")
    else:
        image[:len(raw)] = raw
        print("sin AVB footer; imagen rellenada con ceros")

    args.out.write_bytes(image)
    print(f"{args.out} ({len(image)} bytes, payload {len(raw)})")


if __name__ == "__main__":
    main()
