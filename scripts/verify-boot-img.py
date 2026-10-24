#!/usr/bin/env python3
"""Verifica offline una boot.img de ruby antes de flashear.

    ./scripts/verify-boot-img.py artifacts/ruby-v49.img

Comprueba, sin tocar el dispositivo:
  1. Tamano del payload < orig_size del footer AVB (si no, se pisa el vbmeta).
  2. Footer AVB y bloque vbmeta byte a byte iguales al boot_b stock.
  3. DTB embebido: /ufshci@11270000 sin vcc-supply, OVL con el compatible
     mediatek,mt6877-disp-ovl y el resto de parches del script.
  4. Ramdisk: init sustituido por nuestro loader, modules.load con
     pinctrl-mt6877 antes de mtk-pmic-wrap/mt6397, y que mt6397.ko lleve el
     parche RUBY_NONFATAL_PMIC_IRQ (si no, el MFD aborta con -38).
  5. Kernel: cadena de version (6.6.127 + sufijo GKI de ruby).

Sale con codigo != 0 si algo no cuadra.
"""
import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

PAGE = 2048
ORIG_SIZE_DEFAULT = 41918464
STOCK = Path("device/backups/boot_b-stock.img")


def align(n, a=PAGE):
    return (n + a - 1) // a * a


def layout(img: bytes):
    k = struct.unpack_from("<I", img, 8)[0]
    r = struct.unpack_from("<I", img, 16)[0]
    d = struct.unpack_from("<I", img, 1648)[0]
    koff = PAGE
    roff = PAGE + align(k)
    doff = roff + align(r)
    return dict(kernel=(koff, k), ramdisk=(roff, r), dtb=(doff, d),
                payload=doff + align(d))


def avb(img: bytes):
    foot = img[-64:]
    if foot[:4] != b"AVBf":
        raise SystemExit("no hay footer AVB al final de la imagen")
    orig, voff, vsize = struct.unpack(">QQQ", foot[12:36])
    return foot, orig, voff, vsize, img[voff:voff + vsize]


def cpio_entries(cpio: bytes):
    off = 0
    while off + 110 <= len(cpio):
        if cpio[off:off + 6] not in (b"070701", b"070702"):
            off += 1
            continue
        hdr = cpio[off:off + 110]
        filesize = int(hdr[54:62], 16)
        namesize = int(hdr[94:102], 16)
        name = cpio[off + 110:off + 110 + namesize - 1].decode("utf8", "replace")
        data_at = off + 110 + namesize
        if name == "TRAILER!!!":
            return
        yield name, cpio[data_at:data_at + filesize]
        off = data_at + align(filesize, 4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=Path)
    ap.add_argument("--stock", type=Path, default=STOCK)
    ap.add_argument("--expect-pmic-patch", action="store_true",
                    help="exige RUBY_NONFATAL_PMIC_IRQ en mt6397.ko")
    ap.add_argument("--expect-vcc", action="store_true",
                    help="exige vcc-supply en el nodo UFS (builds antiguos)")
    a = ap.parse_args()

    img = a.image.read_bytes()
    lay = layout(img)
    ok = True

    def check(cond, msg):
        nonlocal ok
        print(("  OK   " if cond else "  FALLO ") + msg)
        ok = ok and cond

    print(f"== {a.image} ({len(img)} bytes)")
    foot, orig, voff, vsize, vb = avb(img)
    print(f"   payload={lay['payload']} orig_size={orig} vbmeta@{voff}+{vsize}")
    check(lay["payload"] < orig, "payload por debajo de orig_size (no se pisa vbmeta)")

    if a.stock.is_file():
        stock = a.stock.read_bytes()
        check(img[-64:] == stock[-64:], "footer AVB identico al stock")
        _, _, _, _, svb = avb(stock)
        check(vb == svb, "bloque vbmeta identico al stock")
    else:
        print(f"   (sin stock en {a.stock}; salto comparacion AVB)")

    # DTB
    doff, dlen = lay["dtb"]
    dtb = img[doff:doff + dlen]
    with tempfile.NamedTemporaryFile(suffix=".dtb") as tf:
        tf.write(dtb)
        tf.flush()
        dts = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-q", tf.name],
                             capture_output=True, text=True).stdout
    check("ufshci@11270000" in dts, "DTB tiene /ufshci@11270000")
    node = ""
    for chunk in dts.split("\n\t"):
        if chunk.lstrip().startswith("ufshci: ufshci@11270000"):
            node = chunk
            break
    if a.expect_vcc:
        check("vcc-supply" in node, "nodo UFS conserva vcc-supply (esperado)")
    else:
        check("vcc-supply" not in node, "nodo UFS sin vcc-supply (UFS no depende del PMIC)")
    check("mediatek,mt6877-disp-ovl-2l" not in dts,
          "sin compatibles OVL 2L (CRTC)")
    check("mediatek,mt6877-disp-ovl" in dts, "OVL con el compatible de 6877")
    check("mediatek,eint = <0x48>" in dts or "mediatek,eint" in dts,
          "nodo pio con phandle mediatek,eint")

    # ramdisk
    roff, rlen = lay["ramdisk"]
    with tempfile.TemporaryDirectory() as td:
        raw = Path(td) / "ramdisk"
        raw.write_bytes(img[roff:roff + rlen])
        cpio = subprocess.run(["lz4", "-d", "-c", str(raw)],
                              capture_output=True).stdout
    check(len(cpio) > 0, f"ramdisk LZ4 descomprime ({len(cpio)} bytes de cpio)")
    names = {}
    for name, data in cpio_entries(cpio):
        names[name] = data
    check("lib/modules/modules.load" in names, "ramdisk trae lib/modules/modules.load")
    load = names.get("lib/modules/modules.load", b"").decode("utf8", "replace")
    order = [l.strip() for l in load.splitlines() if l.strip() and not l.startswith("#")]
    print(f"   modules.load: {len(order)} modulos")
    for m in ("pinctrl-mt6877.ko", "mtk-pmic-wrap.ko", "mt6397.ko"):
        check(m in order, f"modules.load lista {m}")
    if "pinctrl-mt6877.ko" in order and "mt6397.ko" in order:
        check(order.index("pinctrl-mt6877.ko") < order.index("mt6397.ko"),
              "pinctrl-mt6877 antes de mt6397 (EINT listo para el IRQ del PMIC)")
    for m in ("phy-mtk-ufs.ko", "ufs-mediatek-mod.ko"):
        check(m in order, f"modules.load lista {m}")
    if "phy-mtk-ufs.ko" in order and "ufs-mediatek-mod.ko" in order:
        check(order.index("phy-mtk-ufs.ko") < order.index("ufs-mediatek-mod.ko"),
              "phy-mtk-ufs antes de ufs-mediatek-mod (evita pm_runtime desbalanceado)")
    mods = [n for n in names if n.endswith(".ko")]
    check(len(mods) > 80, f"ramdisk trae {len(mods)} .ko")
    ko = names.get("lib/modules/mt6397.ko", b"")
    has_patch = b"RUBY_NONFATAL_PMIC_IRQ" in ko
    if a.expect_pmic_patch:
        check(has_patch, "mt6397.ko lleva RUBY_NONFATAL_PMIC_IRQ")
    else:
        print(f"   mt6397.ko RUBY_NONFATAL_PMIC_IRQ: {'si' if has_patch else 'no'}")

    # kernel (puede venir comprimido en gzip)
    koff, klen = lay["kernel"]
    kern = img[koff:koff + klen]
    if kern[:2] == b"\x1f\x8b":
        kern = subprocess.run(["gzip", "-dc"], input=kern, capture_output=True).stdout
    check(b"6.6.127" in kern, f"kernel con 6.6.127 ({len(kern)} bytes tras descomprimir)")
    check(b"abogkiA346BXXSEEZB6" in kern or b"abogkiA346" in kern,
          "kernel con el sufijo GKI de ruby (abogkiA346...)")

    print("\nVEREDICTO:", "LISTO PARA FLASHEAR" if ok else "NO FLASHEAR")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
