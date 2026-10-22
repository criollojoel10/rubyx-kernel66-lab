#!/usr/bin/env python3
"""Porta los drivers de carga de ruby (4.19) al arbol 6.6 de MTK mt6877.

Los drivers de chip de ruby (mp2762, ln8410, bq25980, sc8561, max77932,
xmusb350) viven en el arbol 4.19 de ruby, en rutas estandar de Linux, y no
existen en 6.6 (ni en upstream ni en el arbol publico de MTK 6.6).

Fuente: sources/ruby-4.19/drivers/power/supply/{mps,ln,ti,southchip,maxim,xiaomi}
Salida: port/charger/drivers/<subdir>/

Se copian tal cual; las adaptaciones de API se hacen sobre la copia (asi el
diff contra el 4.19 es revisable).

Uso: scripts/port-charger.py
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "sources/ruby-4.19/drivers/power/supply"
DST_ROOT = ROOT / "port/charger/drivers"

# subdir -> (ficheros, symbol Kconfig, nombre de modulo)
GROUPS = {
    "mps": (["mp2762.c", "mp2762.h"], "RUBY_MP2762", "mp2762"),
    "ln": (["ln8410.c", "ln8410.h"], "RUBY_LN8410", "ln8410"),
    "ti": (["bq25980.c", "bq25980.h", "bq28z610.c"], "RUBY_BQ25980", "bq25980"),
    "southchip": (["sc8561.c", "sc8561.h"], "RUBY_SC8561", "sc8561"),
    "maxim": (["max77932.c"], "RUBY_MAX77932", "max77932"),
    "xiaomi": (["xmusb350.c", "pd_cp_manager.c", "pd_cp_manager.h",
                "qc_cp_manager.c", "qc_cp_manager.h"], "RUBY_XMUSB350", "xmusb350"),
}

KCONFIG = """#
# Driver de carga de ruby portado a 6.6
#

config {symbol}
	tristate "{name}"
	help
	  Driver de carga {name} de Xiaomi ruby, portado desde el
	  kernel 4.19 de ruby al arbol 6.6 de MTK mt6877.
"""

MAKEFILE = """# Driver de carga de ruby portado a 6.6
obj-$(CONFIG_{symbol}) += {module}.o
"""


def main() -> None:
    if not SRC_ROOT.exists():
        raise SystemExit(f"falta {SRC_ROOT}; descarga el arbol 4.19 de ruby")
    if DST_ROOT.exists():
        shutil.rmtree(DST_ROOT)
    for subdir, (files, symbol, module) in GROUPS.items():
        dst = DST_ROOT / subdir
        dst.mkdir(parents=True, exist_ok=True)
        for f in files:
            src = SRC_ROOT / subdir / f
            if not src.exists():
                print(f"[charger] AVISO: no existe {src}")
                continue
            shutil.copy2(src, dst / f)
        objs = " ".join(
            f[:-2] + ".o" for f in files
            if f.endswith(".c") and f not in ("pd_cp_manager.c", "qc_cp_manager.c")
        )
        (dst / "Makefile").write_text(
            f"# Driver de carga de ruby portado a 6.6\n"
            f"obj-$(CONFIG_{symbol}) += {module}.o\n"
            f"{module}-y += {objs}\n"
        )
        (dst / "Kconfig").write_text(KCONFIG.format(symbol=symbol, name=module))
        print(f"[charger] {subdir}: {len(files)} ficheros -> {dst}")


if __name__ == "__main__":
    main()
