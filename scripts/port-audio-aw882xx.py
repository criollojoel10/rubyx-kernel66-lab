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
        # hwid.h no existe en 6.6: get_hw_sku() se sustituye por un stub
        t = t.replace('#include <linux/hwid.h>',
                      '/* ruby: linux/hwid.h no existe en 6.6 */\n'
                      '#include <linux/extcon.h>\n'
                      '#ifndef get_hw_sku\n'
                      'static inline const char *get_hw_sku(void)\n'
                      '{ return "ruby"; }\n'
                      '#endif')
        # 6.4+: las clases usan device_attribute y ya no tienen .owner
        t = t.replace('struct class_attribute', 'struct device_attribute')
        t = t.replace('\t.owner = THIS_MODULE,\n', '')
        # 5.10+: get_fs/set_fs/KERNEL_DS ya no existen
        t = t.replace('\tmm_segment_t fs;\n', '')
        t = t.replace('\tfs = get_fs();\n\tset_fs(KERNEL_DS);\n\n', '')
        t = t.replace('\tset_fs(fs);\n\n', '')
        t = t.replace('\tset_fs(fs);\n', '')
        # class_create() sin THIS_MODULE desde 6.4
        t = re.sub(r'class_create\(THIS_MODULE,\s*', 'class_create(', t)
        # 6.6: __ATTR() + class_create_file() ya no existen para las clases:
        # se usa DEVICE_ATTR() + device_create_file(class_dev(...), &attr.dev_attr)
        t = t.replace('class_att_', 'class_attr_')
        # juego legacy: struct class_attribute + __ATTR() -> DEVICE_ATTR()
        t = re.sub(
            r'static struct class_attribute (\w+)\s*=\s*\\?\s*\n\s*__ATTR\(\s*(\w+)\s*,',
            r'static DEVICE_ATTR(\2,', t)
        # juego moderno: se mantiene el struct device_attribute, pero el
        # registro pasa por device_create_file(class_dev(...), &attr)
        t = re.sub(
            r'class_create_file\(&(\w+),\s*&class_attr_(\w+)\)',
            r'device_create_file(class_dev(&\1), &class_attr_\2)', t)
        if 'class_dev(' in t and 'linux/device/class.h' not in t:
            t = t.replace('#include <linux/module.h>',
                          '#include <linux/module.h>\n#include <linux/device/class.h>', 1)
        # devm_gpio_* viven en gpio/consumer.h desde 5.x
        if 'devm_gpio_' in t and 'linux/gpio/consumer.h' not in t:
            t = t.replace('#include <linux/module.h>',
                          '#include <linux/module.h>\n#include <linux/gpio/consumer.h>', 1)
        # 6.x: probe() del driver de i2c ya no recibe el device_id
        t = t.replace(
            'static int aw882xx_i2c_probe(struct i2c_client *i2c,\n'
            '\t\t\t\tconst struct i2c_device_id *id)',
            'static int aw882xx_i2c_probe(struct i2c_client *i2c)')
        # 6.x: remove() del driver de i2c devuelve void
        t = t.replace('static int aw882xx_i2c_remove(struct i2c_client *i2c)',
                      'static void aw882xx_i2c_remove(struct i2c_client *i2c)')
        # ... y su cuerpo no puede devolver valor
        t = re.sub(r'(static void aw882xx_i2c_remove\(struct i2c_client \*i2c\)\n\{.*?\n)\treturn 0;\n',
                   r'\1', t, flags=re.S)
        # 6.2+: devm_gpio_free() ya no existe (los GPIO devm se liberan solos)
        t = re.sub(r'\n\tif \(gpio_is_valid\(aw882xx->\w+\)\)\n\t\tdevm_gpio_free\(&i2c->dev, aw882xx->\w+\);', '', t)
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
