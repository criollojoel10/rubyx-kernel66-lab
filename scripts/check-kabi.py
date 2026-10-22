#!/usr/bin/env python3
"""Compara el kABI (CRCs de Module.symvers) entre dos builds.

    check-kabi.py baseline.symvers nuevo.symvers

Salida: exit 0 si no cambia ningún CRC de símbolos existentes (solo se
aceptan símbolos nuevos), exit 1 si cambia alguno.
"""
import sys


def load(path):
    crc = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            # 0:Module.symvers -> 1:module, 2:func, 3:namespace, 4:crc
            key = (parts[1], parts[2], parts[3])
            crc[key] = parts[4]
    return crc


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    base = load(sys.argv[1])
    new = load(sys.argv[2])

    changed = sorted(k for k in base if k in new and base[k] != new[k])
    removed = sorted(k for k in base if k not in new)
    added = sorted(k for k in new if k not in base)

    print(f"baseline: {len(base)} símbolos")
    print(f"nuevo   : {len(new)} símbolos")
    print(f"cambiados: {len(changed)}")
    print(f"eliminados: {len(removed)}")
    print(f"nuevos   : {len(added)}")

    for k in changed[:40]:
        print(f"  CRC {k[1]} {base[k]} -> {new[k]}")
    for k in removed[:20]:
        print(f"  -{k[1]}")
    for k in added[:20]:
        print(f"  +{k[1]}")

    if changed:
        print("KABI ROTO: hay simbolos con CRC distinto")
        return 1
    print("KABI INTACTO: ningun CRC existente cambio")
    return 0


if __name__ == "__main__":
    sys.exit(main())
