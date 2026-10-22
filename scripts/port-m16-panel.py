#!/usr/bin/env python3
"""Porta a la API mediatek_v2 (6.6) los paneles m16 de ruby.

ruby tiene tres variantes de panel m16 (segun la ROM):
  36-02-0b, 42-0d-0a y 45-02-0c. El dtbo declara panel1@0 = 42-0d-0a y
  panel2@0 = 36-02-0b, y el cmdline del kernel stock selecciona el 42-0d-0a
  (panel-m16-42-0d-0a-dsc-vdo.oled_wp=...).

El esqueleto es el panel de referencia 6.6 del A34
(panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c, que ya usa mediatek_v2) y se
sustituyen la identidad, los timings y la secuencia DCS por los del panel
m16 correspondiente del kernel 4.19 de ruby.

  DCS y timings : sources/ruby-4.19/drivers/gpu/drm/panel/panel-m16-<p>.c
  esqueleto 6.6  : sources/a34x/.../panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c
  salida         : port/display/panel-m16-<p>-dsc-vdo.c
                   port/display/include/panel-m16-<p>-dsc-vdo.h
                   port/display/m16-<p>-init.inc

Uso: scripts/port-m16-panel.py [panel ...]
     (sin argumentos: los tres)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF_C = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.c"
REF_H = ROOT / "sources/a34x/kernel/kernel_device_modules-6.6/drivers/gpu/drm/panel/include/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.h"
RUBY_DIR = ROOT / "sources/ruby-4.19/drivers/gpu/drm/panel"

OUT_DIR = ROOT / "port/display"

PANELS = {
    "36-02-0b": {"compat": "m16_36_02_0b_dsc_vdo,lcm",
                  "kconfig": "DRM_PANEL_M16_36_02_0B_DSC_VDO"},
    "42-0d-0a": {"compat": "m16_42_0d_0a_dsc_vdo,lcm",
                  "kconfig": "DRM_PANEL_M16_42_0D_0A_DSC_VDO"},
    "45-02-0c": {"compat": "m16_45_02_0c_dsc_vdo,lcm",
                  "kconfig": "DRM_PANEL_M16_45_02_0C_DSC_VDO"},
}


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


def emit_inc(entries, panel: str) -> str:
    lines = [
        "/* SPDX-License-Identifier: GPL-2.0 */",
        f"/* Secuencia de inicializacion DCS del panel m16 {panel} de ruby.",
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
        if cmd == "REGFLAG_END_OF_TABLE":
            # sentinela de fin de tabla: no es un comando DCS
            lines.append("\t/* fin de la tabla DCS */")
            continue
        if cmd == "REGFLAG_RESET_LOW":
            lines.append("\t/* reset bajo */")
            continue
        if cmd == "REGFLAG_RESET_HIGH":
            lines.append("\t/* reset alto */")
            continue
        args = ", ".join([cmd] + plist)
        lines.append(f"\tlcm_dcs_write_seq_static(ctx, {args});")
    lines.append("")
    return "\n".join(lines)


def ruby_modes(src: str):
    """Extrae los dos modos (60/90 Hz) del panel 4.19: clock, HFP, VFP."""
    modes = []
    for name in ("mode_60hz", "mode_90hz"):
        m = re.search(r"\." + name + r"\s*=\s*\{(.*?)\n\t\};", src, re.S)
        if not m:
            continue
        body = m.group(1)
        def num(key, default=0):
            mm = re.search(r"\." + key + r"\s*=\s*(\d+)", body)
            return int(mm.group(1)) if mm else default
        # los offsets vienen como "1080 + 20" o "2400 + 2452"
        def off(key):
            mm = re.search(r"\." + key + r"\s*=\s*\d+\s*\+\s*(\d+)", body)
            return int(mm.group(1)) if mm else num(key)
        modes.append({
            "clock": num("clock"),
            "hfp": off("hsync_start"),
            "vfp": off("vsync_start"),
            "hsa": off("hsync_end") - off("hsync_start") if off("hsync_end") >= off("hsync_start") else 8,
            "vsa": 4,
        })
    return modes


def build_header(panel: str, ruby_src: str) -> str:
    ref = REF_H.read_text()
    ref = ref.replace("PANEL_NT36672C_FHDP_DSI_VDO_DSC_TXD_BOE",
                      f"PANEL_M16_{panel.upper().replace('-', '_')}_DSC_VDO")
    # geometria y timings reales del panel de ruby
    def rconst(name, default=None):
        m = re.search(r"^#define\s+" + name + r"\s+\(?([^)\n]+)\)?\s*$", ruby_src, re.M)
        return m.group(1).strip() if m else default
    reemplazos = {
        "FRAME_WIDTH": rconst("FRAME_WIDTH", "1080"),
        "FRAME_HEIGHT": rconst("FRAME_HEIGHT", "2400"),
        "DATA_RATE": rconst("DATA_RATE", "831"),
        "PHYSICAL_WIDTH": rconst("PHYSICAL_WIDTH", "69552"),
        "PHYSICAL_HEIGHT": rconst("PHYSICAL_HEIGHT", "154560"),
    }
    for k, v in reemplazos.items():
        ref = re.sub(r"^#define\s+" + k + r"\s+.*$", f"#define {k} {v}", ref, flags=re.M)
    # modos: 60 Hz (mode 0) y 90 Hz (mode 1) con los valores del panel
    modes = ruby_modes(ruby_src)
    if len(modes) >= 2:
        m0, m1 = modes[0], modes[1]
        ref = re.sub(r"^#define\s+MODE_0_VFP\s+.*$", f"#define MODE_0_VFP                  {m0['vfp']}", ref, flags=re.M)
        ref = re.sub(r"^#define\s+MODE_0_HFP\s+.*$", f"#define MODE_0_HFP                  {m0['hfp']}", ref, flags=re.M)
        ref = re.sub(r"^#define\s+MODE_1_VFP\s+.*$", f"#define MODE_1_VFP                  {m1['vfp']}", ref, flags=re.M)
        ref = re.sub(r"^#define\s+MODE_1_HFP\s+.*$", f"#define MODE_1_HFP                  {m1['hfp']}", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_0_FPS\s+.*$", "#define MODE_0_FPS                  60", ref, flags=re.M)
    ref = re.sub(r"^#define\s+MODE_1_FPS\s+.*$", "#define MODE_1_FPS                  90", ref, flags=re.M)
    # tablas RC del panel de ruby (rate control del DSC)
    def tabla(nombre):
        m = re.search(r"static\s+\w+\s+" + nombre + r"\[\d+\]\s*=\s*\{(.*?)\};", ruby_src, re.S)
        return m.group(1).strip() if m else None

    rc = []
    for nombre, tipo in (("rc_buf_thresh", "unsigned int"),
                          ("range_min_qp", "unsigned int"),
                          ("range_max_qp", "unsigned int"),
                          ("range_bpg_ofs", "int")):
        vals = tabla(nombre)
        if vals:
            rc.append(f"static {tipo} {nombre}[] = {{{vals}}};")
    guard = f"#endif /* PANEL_M16_{panel.upper().replace('-', '_')}_DSC_VDO */"
    if rc:
        ref = ref.replace(guard, "\n".join(rc) + "\n\n" + guard)
    return ref


def build_c(entries, panel: str, compat: str, ruby_src: str) -> str:
    s = REF_C.read_text()
    s = s.replace("include/panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe.h",
                  f"include/panel-m16-{panel}-dsc-vdo.h")
    s = s.replace('"nt36672c,vdo,dsc,boe"', f'"{compat}"')
    s = s.replace("panel-nt36672c-fhdp-dsi-vdo-dsc-txd-boe", f"panel-m16-{panel}-dsc-vdo")
    s = s.replace("nt36672c", f"m16-{panel}")
    s = s.replace("NT36672C_FHDP_DSI_VDO_DSC_TXD_BOE", f"M16_{panel.upper().replace('-', '_')}_DSC_VDO")

    # secuencia DCS: el bloque del panel de referencia se sustituye por el .inc
    marker = "static void lcm_panel_init(struct lcm *ctx)\n{"
    i = s.index(marker)
    start = s.index("\tlcm_dcs_write_seq_static(ctx,", i)
    end = s.index("\n}\n", start)
    block = s[start:end]
    tail = block.rstrip().splitlines()[-1]
    if "msleep" not in tail and "udelay" not in tail:
        raise SystemExit(f"el bloque DCS no termina en un delay: {tail!r}")
    s = s[:start] + (f'\t/* m16 {panel}: secuencia DCS real del panel de ruby */\n'
                     f'#include "m16-{panel}-init.inc"\n') + s[end:]

    # clocks reales del panel
    modes = ruby_modes(ruby_src)
    clocks = list(re.findall(r"\.clock\s*=\s*(\d+),", s))
    for idx, old in enumerate(clocks[:2]):
        if idx < len(modes):
            new = str(modes[idx]["clock"])
            if old != new:
                s = s.replace(f".clock = {old},", f".clock = {new},", 1)
    return s


def main() -> None:
    paneles = sys.argv[1:] or list(PANELS)
    for f in (REF_C, REF_H):
        if not f.exists():
            raise SystemExit(f"falta {f}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "include").mkdir(parents=True, exist_ok=True)
    for panel in paneles:
        if panel not in PANELS:
            raise SystemExit(f"panel desconocido: {panel}")
        ruby = RUBY_DIR / f"panel-m16-{panel}-dsc-vdo.c"
        if not ruby.exists():
            raise SystemExit(f"falta {ruby}")
        ruby_src = ruby.read_text()
        entries = parse_init_table(ruby_src)
        compat = PANELS[panel]["compat"]
        (OUT_DIR / f"m16-{panel}-init.inc").write_text(emit_inc(entries, panel))
        (OUT_DIR / "include" / f"panel-m16-{panel}-dsc-vdo.h").write_text(
            build_header(panel, ruby_src))
        (OUT_DIR / f"panel-m16-{panel}-dsc-vdo.c").write_text(
            build_c(entries, panel, compat, ruby_src))
        print(f"[panel] {panel}: {len(entries)} entradas DCS -> port/display/")


if __name__ == "__main__":
    main()
