#!/usr/bin/env python3
"""Prepara el driver Focaltech FT3680 (SPI) para el kernel 6.6 de ruby.

Base: driver MTK 6.6 `focal_FT3519` (nativo de 6.6, transporte SPI v2,
notificacion de display mediatek_v2) del arbol publico de MTK para MT6877.
Se adapta al chip que monta ruby: Focaltech **FT3680** por SPI3.

Fuente: sources/mtk-6.6-mt6877/kernel_device_modules/drivers/input/touchscreen/focal_FT3519
Salida: port/touch/focaltech_3680/

Datos del chip (sacados del driver 4.19 de ruby,
sources/ruby-4.19/drivers/input/touchscreen/focaltech_3680/):
  _FT3680 = 0x3680008A   -> tipo 0x8A
  id de chip 0x56/0x62, rom 0x56/0x62, pb 0x56/0xE2
  compatible en el DT: "focaltech,3680-spi"

Uso: scripts/port-touch-focal3680.py
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "sources/mtk-6.6-mt6877/kernel_device_modules/drivers/input"
       / "touchscreen/focal_FT3519")
DST = ROOT / "port/touch/focaltech_3680"

SKIP_DIRS = {"focaltech_test"}
SKIP_SUFFIX = (".i",)


def copy_tree() -> None:
    if not SRC.exists():
        raise SystemExit(f"falta {SRC}; ejecuta scripts/fetch-mtk-6.6-mt6877.sh")
    if DST.exists():
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST)
    for p in sorted(DST.rglob("*"), reverse=True):
        if p.is_dir() and p.name in SKIP_DIRS:
            shutil.rmtree(p)
            continue
        if p.is_file() and p.suffix in SKIP_SUFFIX:
            p.unlink()
    print(f"[touch] copiado {SRC.name} -> {DST}")


def patch_file(name: str, replacements: list[tuple[str, str]]) -> None:
    path = DST / name
    text = path.read_text()
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"no se encontro en {name}: {old!r}")
        text = text.replace(old, new, 1)
    path.write_text(text)
    print(f"[touch] parcheado {name}")


def main() -> None:
    copy_tree()

    # 1) chip id del FT3680
    patch_file("focaltech_config.h", [
        ("#define _FT3519             0x35190489",
         "#define _FT3519             0x35190489\n"
         "#define _FT3680             0x3680008A"),
        ("#define FTS_CHIP_TYPE   _FT3519",
         "#define FTS_CHIP_TYPE   _FT3680"),
    ])

    # 2) tabla de ids: entrada del FT3680 (id/rom/pb) tomada del 4.19
    patch_file("focaltech_common.h", [
        ("#define FTS_CHIP_TYPE_MAPPING {{0x89, 0x54, 0x52, 0x54, 0x52, 0x54, 0x5B, 0x54, 0x5E}}",
         "#define FTS_CHIP_TYPE_MAPPING {{0x89, 0x54, 0x52, 0x54, 0x52, 0x54, 0x5B, 0x54, 0x5E}, \\\n"
         "                          {0x8A, 0x56, 0x62, 0x56, 0x62, 0x56, 0xE2, 0x00, 0x00}}"),
    ])

    # 3) compatible del nodo SPI de ruby
    patch_file("focaltech_spi_v2.c", [
        ('    {.compatible = "focaltech,fts", },',
         '    {.compatible = "focaltech,fts", },\n'
         '    {.compatible = "focaltech,3680-spi", },'),
    ])

    # 4) Kconfig propio
    (DST / "Kconfig").write_text(
        "#\n# Focaltech FT3680 (SPI) para ruby\n#\n\n"
        "config TOUCHSCREEN_FOCALTECH_3680\n"
        "    tristate \"Focaltech FT3680 touchscreen (SPI)\"\n"
        "    help\n"
        "      Driver del panel tactil Focaltech FT3680 que monta el\n"
        "      Xiaomi ruby (m16) sobre SPI3.\n"
    )
    print("[touch] Kconfig escrito")

    # 5) firmware de ejemplo: los .i que el driver incluye no vienen en el
    # arbol publico de MTK. Se pone un byte para que compile; la ruta de
    # upgrade solo se usa si el chip no trae firmware valido en ROM.
    fw = DST / "include/firmware/FT3519_X6881_V3C_D04_20250428_app.i"
    fw.parent.mkdir(parents=True, exist_ok=True)
    fw.write_text("0x00,\n")
    pb = DST / "include/pramboot/FT5452J_Pramboot_V4.1_20210427.i"
    pb.parent.mkdir(parents=True, exist_ok=True)
    pb.write_text("0x00,\n")
    print("[touch] firmware de ejemplo creado (byte 0x00)")

    # 6) Makefile: modulo propio
    (DST / "Makefile").write_text(
        "# Focaltech FT3680 (SPI) para ruby.\n"
        "obj-$(CONFIG_TOUCHSCREEN_FOCALTECH_3680) += focaltech_3680.o\n"
        "focaltech_3680-y += focaltech_core.o \\\n"
        "\t\tfocaltech_ex_fun.o \\\n"
        "\t\tfocaltech_ex_mode.o \\\n"
        "\t\tfocaltech_gesture.o \\\n"
        "\t\tfocaltech_esdcheck.o \\\n"
        "\t\tfocaltech_point_report_check.o \\\n"
        "\t\tfocaltech_proximity.o \\\n"
        "\t\tfocaltech_spi_v2.o \\\n"
        "\t\tfocaltech_debug.o \\\n"
        "\t\tfocaltech_hp.o \\\n"
        "\t\tfocaltech_flash.o \\\n"
        "\t\tfocaltech_flash/focaltech_upgrade_ft3519.o\n"
    )
    print("[touch] Makefile escrito")


if __name__ == "__main__":
    main()
