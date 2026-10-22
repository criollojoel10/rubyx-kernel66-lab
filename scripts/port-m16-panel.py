#!/usr/bin/env python3
"""Porta a la API mediatek_v2 (6.6) el panel REAL de ruby: m16 42-0d-0a.

El panel lo declara el propio cmdline del kernel stock:
    panel-m16-42-0d-0a-dsc-vdo.oled_wp=...
y el dtbo de ruby lo instancia como panel2@0 con el compatible
"m16_42_0d_0a_dsc_vdo,lcm".

Esqueleto: el panel de referencia 6.6 del A34 (panel-nt36672c...boe), que ya
esta escrito para la API mediatek_v2. Se sustituyen la identidad, los
timings y la secuencia DCS por los del m16 42-0d-0a del 4.19 de ruby.

Fuentes:
  esqueleto v2 : sources/a34x/kernel-6.6/drivers/gpu/drm/panel/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c
                 + su include/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.h
  DCS y timings : sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-42-0d-0a-dsc-vdo.c

Salida:
  port/display/panel-m16-42-0d-0a-dsc-vdo.c
  port/display/include/panel-m16-42-0d-0a-dsc-vdo.h
  port/display/m16-42-0d-0a-init.inc

Uso: scripts/port-m16-panel.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF_C = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c"
REF_H = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel/include/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.h"
RUBY = ROOT / "sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-42-0d-0a-dsc-vdo.c"

OUT_DIR = ROOT / "port/display"
OUT_C = OUT_DIR / "panel-m16-42-0d-0a-dsc-vdo.c"
OUT_H = OUT_DIR / "include/panel-m16-42-0d-0a-dsc-vdo.h"
OUT_INC = OUT_DIR / "m16-42-0d-0a-init.inc"

COMPAT = "m16_42_0d_0a_dsc_vdo,lcm"
KCONFIG = "DRM_PANEL_M16_42_0D_0A_DSC_VDO"

# clocks del 42-0d-0a (mode_60hz / mode_90hz) y sus parametros de timing
CLOCKS = {0: 328029, 1: 327759}


def parse_init_table(src: str):
    """Extrae la tabla init_setting_vdo con un parser de llaves.

    El 4.19 de ruby escribe las entradas con los parametros partidos en
    varias lineas y con comentarios; un regex se salta muchas, asi que se
    recorre la tabla contando llaves.
    """
    start = src.index("static struct LCM_setting_table init_setting_vdo[] = {")
    i = src.index("{", src.index("=", start)) + 1
    depth = 1
    body = []
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        body.append(c)
        i += 1
    text = "".join(body)
    # partir por entradas de primer nivel
    entries = []
    depth = 0
    cur = []
    for c in text:
        if c == "{":
            depth += 1
            if depth == 1:
                cur = []
                continue
        if c == "}":
            depth -= 1
            if depth == 0:
                entries.append("".join(cur))
                continue
        if depth >= 1:
            cur.append(c)
    out = []
    for e in entries:
        e = re.sub(r"/\*.*?\*/", " ", e, flags=re.S)   # comentarios
        e = re.sub(r"//[^\n]*", " ", e)               # comentarios de linea
        m = re.match(r"\s*(0x[0-9A-Fa-f]+|REGFLAG_\w+)\s*,\s*(\d+)\s*,\s*\{([^}]*)\}",
                     e, re.S)
        if not m:
            continue
        cmd, delay, params = m.group(1), int(m.group(2)), m.group(3)
        plist = [x.strip() for x in params.split(",") if x.strip()]
        out.append((cmd, delay, plist))
    return out


def emit_inc(entries) -> str:
    lines = [
        "/* SPDX-License-Identifier: GPL-2.0 */",
        "/* Secuencia de inicializacion DCS del panel m16 42-0d-0a de ruby.",
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


def ruby_const(name):
    m = re.search(r"^#define\s+" + name + r"\s+\(?([^)\n]+)\)?\s*$", RUBY.read_text(), re.M)
    return m.group(1).strip() if m else None


def build_header() -> str:
    ref = REF_H.read_text()
    # identidad
    ref = ref.replace("PANEL_NT36672C_FHDP_DSI_VDO_DSC_TXD_BOE",
                      "PANEL_M16_42_0D_0A_DSC_VDO")
    # geometria y timings reales del 42-0d-0a
    reemplazos = {
        "FRAME_WIDTH": 1080,
        "FRAME_HEIGHT": 2400,
        "DATA_RATE": 831,
        "PHYSICAL_WIDTH": 69552,
        "PHYSICAL_HEIGHT": 154560,
    }
    for k, v in reemplazos.items():
        ref = re.sub(r"^#define\s+" + k + r"\s+.*$", f"#define {k} {v}", ref, flags=re.M)
    # modos: 60 Hz (mode 0) y 90 Hz (mode 1) con los valores del 42-0d-0a
    ref = re.sub(r"^#define\s+MODE_0_VFP\s+.*$", "#define MODE_0_VFP                  2452", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_0_HFP\s+.*$", "#define MODE_0_HFP                  20", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_1_VFP\s+.*$", "#define MODE_1_VFP                  828", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_1_HFP\s+.*$", "#define MODE_1_HFP                  20", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_0_FPS\s+.*$", "#define MODE_0_FPS                  60", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_1_FPS\s+.*$", "#define MODE_1_FPS                  90", ref, flags=re.M)
    # tablas RC del panel de ruby (rate control del DSC)
    rsrc = RUBY.read_text()

    def tabla(nombre):
        m = re.search(r"static\s+\w+\s+" + nombre + r"\[\d+\]\s*=\s*\{(.*?)\};", rsrc, re.S)
        return m.group(1).strip() if m else None

    rc = []
    for nombre, tipo in (("rc_buf_thresh", "unsigned int"),
                          ("range_min_qp", "unsigned int"),
                          ("range_max_qp", "unsigned int"),
                          ("range_bpg_ofs", "int")):
        vals = tabla(nombre)
        if vals:
            rc.append(f"static {tipo} {nombre}[] = {{{vals}}};")
    if rc:
        ref = ref.replace("#endif /* PANEL_M16_42_0D_0A_DSC_VDO */",
                          "\n".join(rc) + "\n\n#endif /* PANEL_M16_42_0D_0A_DSC_VDO */")
    return ref


def build_c(entries) -> str:
    s = REF_C.read_text()
    s = s.replace("include/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.h",
                  "include/panel-m16-42-0d-0a-dsc-vdo.h")
    s = s.replace('"nt36672c,vdo,dsc,boe"', f'"{COMPAT}"')
    s = s.replace("panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe", "panel-m16-42-0d-0a-dsc-vdo")
    s = s.replace("nt36672c", "m16-42-0d-0a")
    s = s.replace("NT36672C_FHDP_DSI_VDO_DSC_TXD_BOE", "M16_42_0D_0A_DSC_VDO")

    # secuencia DCS: el bloque del panel de referencia se sustituye por el .inc
    marker = "static void lcm_panel_init(struct lcm *ctx)\n{"
    i = s.index(marker)
    start = s.index("\tlcm_dcs_write_seq_static(ctx,", i)
    end = s.index("\n}\n", start)
    block = s[start:end]
    tail = block.rstrip().splitlines()[-1]
    if "msleep" not in tail and "udelay" not in tail:
        raise SystemExit(f"el bloque DCS no termina en un delay: {tail!r}")
    s = s[:start] + ('\t/* m16 42-0d-0a: secuencia DCS real del panel de ruby */\n'
                     '#include "m16-42-0d-0a-init.inc"\n') + s[end:]

    # clocks reales
    clocks = list(re.findall(r"\.clock\s*=\s*(\d+),", s))
    for idx, old in enumerate(clocks[:2]):
        new = CLOCKS.get(idx, old)
        if old != str(new):
            s = s.replace(f".clock = {old},", f".clock = {new},", 1)
    return s


def main() -> None:
    for f in (REF_C, REF_H, RUBY):
        if not f.exists():
            raise SystemExit(f"falta {f}")
    entries = parse_init_table(RUBY.read_text())
    print(f"[panel] {len(entries)} entradas de init DCS")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "include").mkdir(parents=True, exist_ok=True)
    OUT_INC.write_text(emit_inc(entries))
    OUT_H.write_text(build_header())
    OUT_C.write_text(build_c(entries))
    print(f"[panel] escritos {OUT_C.name}, {OUT_H.name}, {OUT_INC.name}")


if __name__ == "__main__":
    main()
