#!/usr/bin/env python3
"""Porta el altavoz (Awinic aw882xx) y el vibrador (aw8697) de ruby a 6.6.

El 4.19 de ruby trae:
  sound/soc/codecs/aw882xx/          (25 ficheros, ASoC "component")
  drivers/input/misc/aw8697_haptic/  (haptic)

Ningun arbol 6.6 los trae (nada de aw882xx_smartpa ni awinic_haptic), y son
imprescindibles: sin altavoz el telefono no se oye en las llamadas.

Cambios 6.6 que se aplican al copiar:
  * include/linux/hwid.h no existe -> se neutraliza extcon_parse_cmdline()
  * class_create() en 6.4+ ya no takes THIS_MODULE
  * GPIO legacy (gpio_request/gpio_get_value) sigue existiendo

Salida: port/audio/
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "sources/ruby-4.19"
DST = ROOT / "port/audio"

AW882XX = SRC / "sound/soc/codecs/aw882xx"
HAPTIC = SRC / "drivers/input/misc/aw8697_haptic"


def port_aw882xx() -> None:
    dst = DST / "aw882xx"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(AW882XX, dst)
    for junk in dst.rglob("*.o"):
        junk.unlink()
    n = 0
    for c in list(dst.glob("*.c")) + list(dst.glob("*.h")):
        t = c.read_text(errors="ignore")
        orig = t
        # hwid.h no existe en 6.6: el codigo de hwid se deja en stub
        t = t.replace('#include <linux/hwid.h>',
                      '/* ruby: linux/hwid.h no existe en 6.6 */\n'
                      '#include <linux/extcon.h>')
        # class_create() sin THIS_MODULE desde 6.4
        t = re.sub(r'class_create\(THIS_MODULE,\s*', 'class_create(', t)
        if t != orig:
            c.write_text(t)
            n += 1
    print(f"[audio] aw882xx: {len(list(dst.iterdir()))} ficheros, {n} ajustados")


def port_haptic() -> None:
    dst = DST / "aw8697_haptic"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(HAPTIC, dst)
    for junk in dst.rglob("*.o"):
        junk.unlink()
    n = 0
    for c in list(dst.glob("*.c")) + list(dst.glob("*.h")):
        t = c.read_text(errors="ignore")
        orig = t
        t = t.replace('#include <linux/hwid.h>',
                      '/* ruby: linux/hwid.h no existe en 6.6 */\n'
                      '#include <linux/extcon.h>')
        t = re.sub(r'class_create\(THIS_MODULE,\s*', 'class_create(', t)
        if t != orig:
            c.write_text(t)
            n += 1
    print(f"[audio] aw8697_haptic: {len(list(dst.iterdir()))} ficheros, {n} ajustados")


def main() -> None:
    if not AW882XX.exists():
        raise SystemExit(f"falta {AW882XX}; descarga el arbol 4.19 de ruby")
    DST.mkdir(parents=True, exist_ok=True)
    port_aw882xx()
    port_haptic()


if __name__ == "__main__":
    main()
