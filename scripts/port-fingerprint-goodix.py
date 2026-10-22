#!/usr/bin/env python3
"""Porta a 6.6 el driver de huella Goodix de ruby (drivers/input/fingerprint/goodix_cap).

El driver del 4.19 de ruby ya usa el SPI generico (spi_sync) y el UUID de la
TA Goodix (0x8888c03f), que es el que monta ruby; el driver 6.6 publico de
MTK usa la TA de Beanpod (0x7778c03f) y otro chip, asi que no sirve.

Adaptaciones para 6.6:
  - mach/mt_clkmgr.h no existe en 6.6 (y no se usa): se quita el include.
  - linux/earlysuspend.h no existe: se protege el bloque con
    CONFIG_HAS_EARLYSUSPEND, que en 6.6 no se define.

Fuente : sources/ruby-4.19/drivers/input/fingerprint/goodix_cap/
Salida : port/fingerprint/goodix_cap/
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "sources/ruby-4.19/drivers/input/fingerprint/goodix_cap"
DST = ROOT / "port/fingerprint/goodix_cap"

KCONFIG = """#
# Huella Goodix de ruby (SPI)
#

config GOODIX_CAP_FINGERPRINT
	tristate "Goodix fingerprint (SPI)"
	help
	  Driver de la huella Goodix del Xiaomi ruby, portado desde el
	  kernel 4.19 de ruby al arbol 6.6 de MTK.
"""

MAKEFILE = """# Huella Goodix de ruby portada a 6.6
obj-$(CONFIG_GOODIX_CAP_FINGERPRINT) := gf_spi_tee.o gf_spi_factory.o

# el TEEI 400 (Microtrust) es el TEE de ruby
ccflags-y += -I$(srctree)/drivers/tee/teei/400/tz_driver/include/
ccflags-y += -I$(srctree)/drivers/tee/teei/400/common/include/
"""


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"falta {SRC}")
    if DST.exists():
        shutil.rmtree(DST)
    DST.mkdir(parents=True)
    for f in ("gf_spi_tee.c", "gf_spi_factory.c", "gf_spi_tee.h"):
        shutil.copy2(SRC / f, DST / f)

    # --- gf_spi_tee.c -------------------------------------------------
    p = DST / "gf_spi_tee.c"
    s = p.read_text()

    s = s.replace('#include "mach/mt_clkmgr.h"\n', "")

    # earlysuspend: en 6.6 no existe el header ni la API
    s = s.replace("#include <linux/earlysuspend.h>",
                  "#ifdef CONFIG_HAS_EARLYSUSPEND\n#include <linux/earlysuspend.h>\n#endif")
    s = re.sub(r"(\n\s*)register_early_suspend\(&gf_dev->early_suspend\);",
               r"\1#ifdef CONFIG_HAS_EARLYSUSPEND\n\1\tregister_early_suspend(&gf_dev->early_suspend);\n\1#endif", s)
    s = re.sub(r"(\n\s*)unregister_early_suspend\(&gf_dev->early_suspend\);",
               r"\1#ifdef CONFIG_HAS_EARLYSUSPEND\n\1\tunregister_early_suspend(&gf_dev->early_suspend);\n\1#endif", s)
    p.write_text(s)
    print("[fingerprint] gf_spi_tee.c adaptado (mt_clkmgr fuera, earlysuspend protegido)")

    (DST / "Kconfig").write_text(KCONFIG)
    (DST / "Makefile").write_text(MAKEFILE)
    print(f"[fingerprint] escrito {DST}")


if __name__ == "__main__":
    main()
