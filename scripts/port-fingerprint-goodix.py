#!/usr/bin/env python3
"""Adapta el driver de la huella Goodix (4.19 de ruby) al kernel 6.6.

El driver del 4.19 usa el HAL de SPI de MTK (mtk_spi.h / mtk_spi_hal.h) y
el control de clock maestro (mt_spi_enable_master_clk). En 6.6:

  - el HAL mtk_spi.h ya no existe: el driver de SPI (drivers/spi/spi-mt65xx.c)
    gestiona el reloj por si mismo (clk_enable), asi que no hay que tocarlo
    desde fuera;
  - el include de "mtk_spi.h" se quita y se usa el API SPI generico
    (spi_sync / spi_write_then_read), igual que el otro camino del driver
    (CONFIG_SPI_MT65XX);
  - el header de TEE es el de Microtrust (struct TEEC_UUID), que es el que
    necesita el TEEI 400.

Uso: scripts/port-fingerprint-goodix.py
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "sources/ruby-4.19/drivers/input/fingerprint/goodix_cap"
DST = ROOT / "port/fingerprint/goodix_cap"

FICH = ["gf_spi_tee.c", "gf_spi_tee.h", "gf_spi_factory.c"]


def quitar_mtk_spi(t: str) -> str:
    # el HAL de MTK no existe en 6.6
    t = t.replace('#include "mtk_spi.h"\n', '')
    t = t.replace('#include "mtk_spi_hal.h"\n', '')
    # el control de clock lo hace el driver de SPI de 6.6
    t = t.replace("mt_spi_enable_master_clk(gf_dev->spi);",
                  "/* 6.6: el driver de SPI gestiona el clock maestro */")
    t = t.replace("mt_spi_disable_master_clk(gf_dev->spi);",
                  "/* 6.6: el driver de SPI gestiona el clock maestro */")
    # los prototipos del header
    t = t.replace("""void gf_spi_setup_conf_ree(struct gf_device *gf_dev, u32 speed,
			   enum spi_transfer_mode mode);""",
                  """void gf_spi_setup_conf_ree(struct gf_device *gf_dev, u32 speed,
			   enum spi_transfer_mode mode);
int gf_spi_read_bytes_ree(struct gf_device *gf_dev, u16 addr, u32 data_len,
			  u8 * rx_buf);""")
    # el bloque que usaba mcc (config del SPI) se simplifica: en 6.6 el
    # driver de SPI ya aplica la configuracion del DT
    return t


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"falta {SRC}")
    if DST.exists():
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST)
    for junk in DST.rglob("*.o"):
        junk.unlink()
    for junk in DST.rglob("*.cmd"):
        junk.unlink()

    for f in FICH:
        p = DST / f
        if not p.exists():
            continue
        t = p.read_text(errors="ignore")
        n = quitar_mtk_spi(t)
        if n != t:
            p.write_text(n)
            print(f"[fingerprint] {f}: HAL de MTK eliminado")

    # Kconfig y Makefile propios
    (DST / "Kconfig").write_text(
        "#\n# Driver de la huella Goodix de ruby (4.19 -> 6.6)\n#\n\n"
        "config GOODIX_CAP_FINGERPRINT\n"
        "\ttristate \"Goodix fingerprint sensor (SPI)\"\n"
        "\tdepends on SPI\n"
        "\thelp\n"
        "\t  Driver del sensor de huella Goodix que monta el Xiaomi ruby\n"
        "\t  (SPI, con la TA de Goodix 0x8888c03f sobre Microtrust).\n"
    )
    (DST / "Makefile").write_text(
        "# Driver de la huella Goodix de ruby\n"
        "obj-$(CONFIG_GOODIX_CAP_FINGERPRINT) += goodix_cap.o\n"
        "goodix_cap-y += gf_spi_tee.o gf_spi_factory.o\n"
    )
    print(f"[fingerprint] port en {DST}")


if __name__ == "__main__":
    main()
