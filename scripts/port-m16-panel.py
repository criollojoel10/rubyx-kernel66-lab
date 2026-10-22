#!/usr/bin/env python3
"""Transplanta el panel m16 (36-02-0b) de ruby's 4.19 al driver mediatek_v2 6.6.

Entrada:
  sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c
Salida:
  port/display/m16-36-02-0b-init.inc   (secuencia DCS en C para 6.6)
  port/display/panel-m16-36-02-0b-dsc-vdo.c  (bloque DCS sustituido)

El driver 6.6 de referencia es el panel BOE nt36672c (misma API
mediatek_v2); lo unico especifico del m16 son los timings y la secuencia
de inicializacion, que se toman del 4.19 de ruby.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_419 = ROOT / "sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-36-02-0b-dsc-vdo.c"
INC = ROOT / "port/display/m16-36-02-0b-init.inc"
PORT = ROOT / "port/display/panel-m16-36-02-0b-dsc-vdo.c"

# clocks de ruby's 4.19 (mode_60hz / mode_90hz)
CLOCKS = {0: 328029, 1: 325201}


def parse_init_table(src: str):
    start = src.index("static struct LCM_setting_table init_setting_vdo[] = {")
    end = src.index("};", start)
    body = src[start:end]
    entries = re.findall(
        r"\{\s*(0x[0-9A-Fa-f]+|REGFLAG_\w+)\s*,\s*(\d+)\s*,\s*\{([^}]*)\}\s*\}", body
    )
    out = []
    for cmd, delay, params in entries:
        plist = [p.strip() for p in params.split(",") if p.strip()]
        out.append((cmd, int(delay), plist))
    return out


def emit(entries) -> str:
    lines = [
        "/* SPDX-License-Identifier: GPL-2.0 */",
        "/* Secuencia de inicializacion DCS del panel m16 36-02-0b.",
        " * Generado por scripts/port-m16-panel.py desde el driver 4.19 de ruby.",
        " * No editar a mano: regenerar. */",
        "",
    ]
    for cmd, delay, plist in entries:
        if cmd == "REGFLAG_DELAY":
            lines.append(f"\tmsleep({delay});")
            continue
        if cmd == "REGFLAG_UDELAY":
            lines.append(f"\tudelay({delay});")
            continue
        args = ", ".join([cmd] + plist)
        lines.append(f"\tlcm_dcs_write_seq_static(ctx, {args});")
    lines.append("")
    return "\n".join(lines)


def patch_port(entries) -> bool:
    text = PORT.read_text()

    # 1) Sustituir el bloque DCS de referencia por la secuencia del m16.
    if "m16-36-02-0b-init.inc" in text:
        print("[m16] el .inc ya esta incluido; solo se actualizan los clocks")
    else:
        marker = "static void lcm_panel_init(struct lcm *ctx)\n{"
        i = text.index(marker)
        start = text.index("\tlcm_dcs_write_seq_static(ctx,", i)
        # el bloque acaba en el cierre de la funcion: buscamos la secuencia
        # de llamadas DCS mas el msleep final
        end = text.index("\n}\n", start)
        block = text[start:end]
        # el bloque de referencia acaba con "msleep(20);" o similar
        tail = block.rstrip().splitlines()[-1]
        if "msleep" not in tail and "udelay" not in tail:
            sys.exit(f"el bloque DCS no termina en un delay: {tail!r}")
        new_block = (
            "\t/* m16 36-02-0b: secuencia DCS real del panel de ruby */\n"
            '#include "m16-36-02-0b-init.inc"\n'
        )
        text = text[:start] + new_block + text[end:]
        print(f"[m16] bloque DCS sustituido ({len(block.splitlines())} lineas)")

    # 2) clocks reales del m16 (la referencia usa 291004)
    clocks = list(re.findall(r"\.clock\s*=\s*(\d+),", text))
    for idx, old in enumerate(clocks[:2]):
        new = CLOCKS.get(idx, clocks[idx])
        if old != str(new):
            text = text.replace(f".clock = {old},", f".clock = {new},", 1)
            print(f"[m16] clock {old} -> {new}")

    PORT.write_text(text)
    return True


def main():
    if not SRC_419.exists():
        sys.exit(f"falta {SRC_419}; ejecuta make fetch o descarga ruby-4.19")
    entries = parse_init_table(SRC_419.read_text())
    print(f"[m16] {len(entries)} entradas en init_setting_vdo")
    INC.write_text(emit(entries))
    print(f"[m16] escrito {INC}")
    patch_port(entries)


if __name__ == "__main__":
    main()
