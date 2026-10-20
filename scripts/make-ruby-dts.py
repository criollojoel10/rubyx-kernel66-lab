#!/usr/bin/env python3
"""Genera un DTS mínimo de ruby a partir del mt6877.dts del A34.

No edita el árbol donante. Aplica solo identidad, memoria y consola.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
A34 = ROOT / "sources/a34x"
DEV = A34 / "kernel/kernel_device_modules-6.6"
GKI = A34 / "kernel-6.6"
BASE = DEV / "arch/arm64/boot/dts/mediatek/mt6877.dts"
OUT = ROOT / "dts/ruby-minimal.dts"
DTB = ROOT / "dts/ruby-minimal.dtb"

BOOTARGS = (
    "console=ttyS0,921600n8 earlycon loglevel=8 ignore_loglevel "
    "nokaslr clk_ignore_unused pd_ignore_unused "
    "ramoops.mem_address=0x48090000 ramoops.mem_size=0xe0000 "
    "ramoops.pmsg_size=0x10000 ramoops.console_size=0x40000"
)


def main():
    text = BASE.read_text()

    text = text.replace('model = "MT6877";', 'model = "Xiaomi ruby (minimal)";', 1)
    text = text.replace(
        'compatible = "mediatek,MT6877";',
        'compatible = "xiaomi,ruby", "mediatek,mt6877";', 1)

    mem = (
        '\n\tmemory@40000000 {\n'
        '\t\tdevice_type = "memory";\n'
        '\t\treg = <0x00 0x40000000 0x02 0x00>;\n'
        '\t};\n'
    )
    text = text.replace('\t#size-cells = <2>;\n',
                        '\t#size-cells = <2>;\n' + mem, 1)

    text = re.sub(r'bootargs\s*=\s*".*?";',
                  f'bootargs = "{BOOTARGS}";',
                  text, count=1, flags=re.S)
    text = text.replace('chosen: chosen {',
                        'chosen: chosen {\n\t\tstdout-path = "/serial@11002000";', 1)

    OUT.write_text(text)

    cmd = [
        "cpp", "-nostdinc",
        "-I", str(DEV / "include"),
        "-I", str(GKI / "include"),
        "-I", str(DEV / "arch/arm64/boot/dts"),
        "-I", str(DEV / "arch/arm64/boot/dts/mediatek"),
        "-D__DTS__", "-x", "assembler-with-cpp",
        str(OUT), "-o", "/tmp/ruby-minimal.pp.dts",
    ]
    subprocess.run(cmd, check=True)
    subprocess.run(["dtc", "-I", "dts", "-O", "dtb",
                    "-o", str(DTB), "/tmp/ruby-minimal.pp.dts"], check=True)
    print(f"{OUT} -> {DTB} ({DTB.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
