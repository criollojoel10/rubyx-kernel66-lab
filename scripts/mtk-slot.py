#!/usr/bin/env python3
"""Lee/escribe el bootloader_control de MTK en misc@2048.

    ./scripts/mtk-slot.py status
    ./scripts/mtk-slot.py set b --write
    ./scripts/mtk-slot.py set a --write

Sin --write solo valida y muestra; no toca el dispositivo.
"""
import argparse
import base64
import struct
import subprocess
import sys
import zlib

OFF = 2048
SIZE = 32
MAGIC = 0x42414342


def ssh(cmd):
    return subprocess.check_output(["ssh", "-o", "BatchMode=yes", "termux", cmd])


def read_struct():
    out = ssh('su -c "dd if=/dev/block/by-name/misc bs=1 skip=2048 count=32 2>/dev/null | base64"')
    data = base64.b64decode(out.strip())
    if len(data) != SIZE:
        raise SystemExit(f"leí {len(data)} bytes, esperaba {SIZE}")
    return bytearray(data)


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
    return {
        "suffix": bytes(d[0:4]).rstrip(b"\0").decode(),
        "ver": d[8],
        "A": slot(d[12]),
        "B": slot(d[14]),
    }


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
        # B con un solo intento: si el kernel no llega a init, LK vuelve a A.
        nd[14] = slot_byte(15, 1, 0)
    else:
        raise SystemExit("slot debe ser a o b")
    crc = zlib.crc32(bytes(nd[:28])) & 0xffffffff
    nd[28:32] = struct.pack("<I", crc)
    return nd


def write_struct(nd):
    payload = base64.b64encode(bytes(nd)).decode()
    ssh(f"printf '%s' '{payload}' | base64 -d > /sdcard/bc.bin")
    ssh('su -c "dd if=/sdcard/bc.bin of=/dev/block/by-name/misc bs=1 seek=2048 count=32 conv=notrunc"')
    back = parse(read_struct())
    return back


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["status", "set"])
    ap.add_argument("slot", nargs="?")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    cur = read_struct()
    info = parse(cur)
    print(f"actual: suffix={info['suffix']} ver={info['ver']} A={info['A']} B={info['B']}")
    if args.cmd == "status":
        return

    nd = build(cur, args.slot)
    chk = parse(nd)
    print(f"nuevo : suffix={chk['suffix']} ver={chk['ver']} A={chk['A']} B={chk['B']} crc=OK")
    if not args.write:
        print("dry-run: no se escribió nada")
        return
    back = write_struct(nd)
    ok = back["suffix"] == f"_{args.slot}"
    print(f"leído : {back} {'OK' if ok else 'FALLÓ'}")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
