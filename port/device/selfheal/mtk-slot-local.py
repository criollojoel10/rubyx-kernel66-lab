#!/usr/bin/env python3
"""Lee/escribe el bootloader_control de MTK en misc@2048.
Versión para ejecutarse DENTRO de Android (sin ssh).

Uso:
    python3 mtk-slot-local.py status
    python3 mtk-slot-local.py set a --write
    python3 mtk-slot-local.py set b --write
"""
import argparse
import os
import struct
import sys
import zlib

OFF = 2048
SIZE = 32
MAGIC = 0x42414342
CANDIDATES = ("/dev/block/by-name/misc", "/dev/sdc1")


def misc_path():
    for p in CANDIDATES:
        if os.path.exists(p):
            return p
    raise SystemExit("no encuentro misc")


def read_struct():
    with open(misc_path(), "rb") as f:
        f.seek(OFF)
        d = f.read(SIZE)
    if len(d) != SIZE:
        raise SystemExit(f"leí {len(d)} bytes, esperaba {SIZE}")
    return bytearray(d)


def parse(d):
    magic = struct.unpack("<I", d[4:8])[0]
    if magic != MAGIC:
        raise SystemExit(f"magic inválido 0x{magic:08x}")
    stored = struct.unpack("<I", d[28:32])[0]
    calc = zlib.crc32(bytes(d[:28])) & 0xffffffff
    if stored != calc:
        raise SystemExit(f"CRC inválido stored=0x{stored:08x} calc=0x{calc:08x}")
    def slot(b):
        return {"prio": b & 0xf, "tries": (b >> 4) & 7, "ok": (b >> 7) & 1}
    return {"suffix": bytes(d[0:4]).rstrip(b"\0").decode(),
            "ver": d[8], "A": slot(d[12]), "B": slot(d[14])}


def slot_byte(prio, tries, ok):
    return (prio & 0xf) | ((tries & 7) << 4) | ((ok & 1) << 7)


def build(d, target):
    nd = bytearray(d)
    if target == "a":
        nd[0:4] = b"_a\0\0"
        nd[12] = slot_byte(15, 7, 1)
        nd[14] = slot_byte(14, 7, 0)
    elif target == "b":
        nd[0:4] = b"_b\0\0"
        nd[12] = slot_byte(14, 7, 1)
        nd[14] = slot_byte(15, 1, 0)
    else:
        raise SystemExit("slot debe ser a o b")
    nd[28:32] = struct.pack("<I", zlib.crc32(bytes(nd[:28])) & 0xffffffff)
    return nd


def write_struct(nd):
    with open(misc_path(), "r+b") as f:
        f.seek(OFF)
        f.write(nd)
        f.flush()
        os.fsync(f.fileno())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["status", "set"])
    ap.add_argument("slot", nargs="?")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    info = parse(read_struct())
    print(f"actual: suffix={info['suffix']} ver={info['ver']} A={info['A']} B={info['B']}")
    if args.cmd == "status":
        return
    nd = build(read_struct(), args.slot)
    print(f"nuevo : {parse(nd)}")
    if not args.write:
        print("dry-run: no se escribió nada")
        return
    write_struct(nd)
    back = parse(read_struct())
    print(f"leído : {back} {'OK' if back['suffix'] == '_' + args.slot else 'FALLÓ'}")
    if back["suffix"] != "_" + args.slot:
        sys.exit(1)


if __name__ == "__main__":
    main()
