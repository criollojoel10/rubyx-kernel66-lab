#!/usr/bin/env python3
"""Neutraliza el init de mrdump.ko sin tocar sus simbolos exportados.

Por que:
  ufs-mediatek-dbg.ko referencia mrdump_mini_add_extra_file() y
  mrdump_set_extra_dump(), que solo exporta mrdump.ko. Sin mrdump la cadena
  UFS no carga. Pero el init de mrdump destruye el canal de log (pstore
  console/dmesg) en cuanto se carga, y entonces el arranque falla a ciegas.

Que hace:
  Sobrescribe los primeros bytes de init_module (mrdump_panic_init) con
  "mov w0, #0; autiasp; ret". El modulo carga, registra sus __ksymtab y sus
  CRC, y no ejecuta nada mas. No toca __versions ni vermagic, asi que sigue
  encajando con el kernel de CI.

Uso: scripts/patch-mrdump-init.py <ruta/mrdump.ko> [--revert]
Idempotente: si ya esta parcheado, no hace nada.
"""
import struct
import sys

NEW = bytes.fromhex("00008052" "3f2303d5" "c0035fd6")  # mov w0,#0; autiasp; ret


def sections(d):
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize = struct.unpack_from("<H", d, 0x3A)[0]
    shnum = struct.unpack_from("<H", d, 0x3C)[0]
    shstrndx = struct.unpack_from("<H", d, 0x3E)[0]
    out = {}
    for i in range(shnum):
        off = shoff + i * shentsize
        name, typ = struct.unpack_from("<II", d, off)
        addr, soff, size = struct.unpack_from("<QQQ", d, off + 0x10)
        out[i] = (name, typ, addr, soff, size)
    stroff = out[shstrndx][3]
    named = {}
    for i, (name, typ, addr, soff, size) in out.items():
        end = d.index(b"\0", stroff + name)
        named[d[stroff + name:end].decode()] = (typ, addr, soff, size)
    return named


def symbols(d):
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize = struct.unpack_from("<H", d, 0x3A)[0]
    shnum = struct.unpack_from("<H", d, 0x3C)[0]
    secs = sections(d)
    symtab = next(v for k, v in secs.items() if k == ".symtab")
    strtab = next(v for k, v in secs.items() if k == ".strtab")
    _, _, symoff, symsize = symtab
    _, _, stroff, _ = strtab
    res = {}
    for i in range(symsize // 24):
        o = symoff + i * 24
        nameoff, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", d, o)
        end = d.index(b"\0", stroff + nameoff)
        name = d[stroff + nameoff:end].decode()
        if name:
            res[name] = (shndx, value, size)
    return res, secs


def main():
    if len(sys.argv) < 2:
        print("uso: patch-mrdump-init.py <mrdump.ko> [--revert]", file=sys.stderr)
        return 2
    path = sys.argv[1]
    revert = "--revert" in sys.argv[2:]

    d = bytearray(open(path, "rb").read())
    syms, secs = symbols(bytes(d))
    if "init_module" not in syms:
        print(f"{path}: sin simbolo init_module", file=sys.stderr)
        return 1
    shndx, value, _ = syms["init_module"]
    # indice de seccion -> nombre (secciones() reindexa por nombre)
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize = struct.unpack_from("<H", d, 0x3A)[0]
    shstrndx = struct.unpack_from("<H", d, 0x3E)[0]
    shnum = struct.unpack_from("<H", d, 0x3C)[0]
    stroff = struct.unpack_from("<Q", d, shoff + shstrndx * shentsize + 0x18)[0]
    nameoff = struct.unpack_from("<I", d, shoff + shndx * shentsize)[0]
    end = d.index(b"\0", stroff + nameoff)
    secname = d[stroff + nameoff:end].decode()
    if secname not in secs:
        print(f"{path}: seccion {secname} no encontrada", file=sys.stderr)
        return 1
    _, _, sec_off, sec_size = secs[secname]
    off = sec_off + value
    if revert:
        # El original empieza por paciasp; no guardamos copia, asi que solo
        # avisamos: recompilar/copiar de nuevo el .ko es lo correcto.
        if bytes(d[off:off + 4]) == NEW[:4]:
            print(f"{path}: parcheado; usa el .ko original para revertir")
            return 1
        return 0
    if bytes(d[off:off + len(NEW)]) == NEW:
        print(f"{path}: ya parcheado ({secname}+0x{value:x})")
        return 0
    if secname != ".init.text":
        print(f"{path}: init_module esta en {secname}, se aborta", file=sys.stderr)
        return 1
    print(f"{path}: init_module en {secname}+0x{value:x} -> {d[off:off + 12].hex(' ')}")
    d[off:off + len(NEW)] = NEW
    open(path, "wb").write(d)
    print(f"{path}: init neutralizado -> {NEW.hex(' ')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
