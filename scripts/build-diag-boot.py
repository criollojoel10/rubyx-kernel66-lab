#!/usr/bin/env python3
"""Construye un boot.img de diagnóstico conservando el layout del boot_b stock."""
import argparse
import hashlib
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


def pack_boot_v2(kernel, ramdisk, dtb, page, kernel_addr, ramdisk_addr,
                 tags_addr, dtb_addr, cmdline, os_version):
    """Empaqueta un boot image header v2 sin depender de mkbootimg."""
    align = lambda n: (n + page - 1) // page * page
    header = bytearray(page)
    header[0:8] = b"ANDROID!"
    struct.pack_into("<I", header, 8, len(kernel))
    struct.pack_into("<I", header, 12, kernel_addr)
    struct.pack_into("<I", header, 16, len(ramdisk))
    struct.pack_into("<I", header, 20, ramdisk_addr)
    struct.pack_into("<I", header, 24, 0)
    struct.pack_into("<I", header, 28, 0)
    struct.pack_into("<I", header, 32, tags_addr)
    struct.pack_into("<I", header, 36, page)
    struct.pack_into("<I", header, 40, 2)
    struct.pack_into("<I", header, 44, os_version)
    cmd = cmdline.encode("utf-8")
    if len(cmd) >= 512:
        raise SystemExit("cmdline demasiado largo para header v2")
    header[64:64 + len(cmd)] = cmd
    # id = SHA1(kernel||len(kernel)||ramdisk||len(ramdisk)||0||0||dtb||len(dtb))
    sha = hashlib.sha1()
    for blob in (kernel, ramdisk):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    sha.update(struct.pack("<I", 0))  # second
    sha.update(struct.pack("<I", 0))  # recovery_dtbo
    sha.update(dtb)
    sha.update(struct.pack("<I", len(dtb)))
    header[576:608] = sha.digest()
    struct.pack_into("<I", header, 1632, 0)
    struct.pack_into("<Q", header, 1636, 0)
    struct.pack_into("<I", header, 1644, 1660)
    struct.pack_into("<I", header, 1648, len(dtb))
    struct.pack_into("<Q", header, 1652, dtb_addr)
    out = bytearray()
    out += header
    out += b"\0" * (align(len(header)) - len(header))
    out += kernel
    out += b"\0" * (align(len(kernel)) - len(kernel))
    out += ramdisk
    out += b"\0" * (align(len(ramdisk)) - len(ramdisk))
    out += dtb
    out += b"\0" * (align(len(dtb)) - len(dtb))
    return bytes(out)


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

    raw = pack_boot_v2(
        args.kernel.read_bytes(), args.initramfs.read_bytes(), dtb,
        h["page"], h["kernel_addr"], h["ramdisk_addr"], h["tags_addr"],
        h["dtb_addr"], cmdline, h["os_version"])

    # Conservar tamaño y AVB footer de la imagen original.
    footer = struct.unpack(">4sIIQQQ", orig[-64:-28])
    image = bytearray(len(orig))
    if footer[0] == b"AVBf":
        orig_size, vbmeta_offset, vbmeta_size = footer[3], footer[4], footer[5]
        if len(raw) < orig_size <= vbmeta_offset:
            image[:len(raw)] = raw
            image[vbmeta_offset:vbmeta_offset + vbmeta_size] = orig[vbmeta_offset:vbmeta_offset + vbmeta_size]
            image[-64:] = orig[-64:]
            print(f"AVB footer conservado (vbmeta {vbmeta_offset}+{vbmeta_size})")
        else:
            # El payload ya no cabe donde estaba el vbmeta del boot original.
            # El dispositivo esta desbloqueado (verifiedbootstate=orange) y la
            # firma ya no cuadraba con la imagen parcheada, asi que se ignora:
            # escribimos el payload desde 0 y dejamos el footer al final.
            if len(raw) > len(image) - 64:
                raise SystemExit(f"el payload ({len(raw)}) no cabe en {len(image)} bytes")
            image[:len(raw)] = raw
            image[-64:] = orig[-64:]
            print(f"payload grande: se sobrescribe el vbmeta original (offset {vbmeta_offset})")
    else:
        image[:len(raw)] = raw
        print("sin AVB footer; imagen rellenada con ceros")

    args.out.write_bytes(image)
    print(f"{args.out} ({len(image)} bytes, payload {len(raw)})")


if __name__ == "__main__":
    main()
