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
        # 6.4+: struct class ya no tiene .owner
        t = re.sub(r'\n[ \t]*\.owner[ \t]*=[ \t]*THIS_MODULE,[ \t]*\n', '\n', t)
        # 6.6: la firma de class_attribute usa const struct class *
        #      (const struct class *, const struct class_attribute *, ...)
        def _const_sig(m):
            sig = m.group(0)
            sig = re.sub(r'\bstruct(\s+class\s*\*\s*class,)', r'const struct\1', sig)
            sig = re.sub(r'\bstruct(\s+class_attribute\s*\*\s*attr,)',
                         r'const struct\1', sig)
            return sig
        t = re.sub(r'static ssize_t \w+\([^)]*\)', _const_sig, t)
        # loff_t con %d: el valor es un entero small
        t = t.replace('loff_t pos;', 'int pos;')
        # el %d de un loff_t (pos)
        t = t.replace('pos:%d', 'pos:%lld')
        t = t.replace('"channel:%d pos:%d \\n"', '"channel:%d pos:%lld \\n"')
        t = t.replace('"channel:%d pos:%d \\n"', '"channel:%d pos:%lld \\n"')
        t = t.replace('loff_t offset', 'long offset')
        # 6.2+: devm_gpio_free() ya no existe (los gpio devm se liberan solos)
        t = re.sub(r'\n[ \t]*devm_gpio_free\([^)]*\);', '', t)
        # 6.x: el probe() de i2c ya no recibe el i2c_device_id
        t = re.sub(r'static int (\w*probe)\(struct i2c_client \*(\w+),\s*\n?\s*'
                   r'const struct i2c_device_id \*\w+\)',
                   r'static int \1(struct i2c_client *\2)', t)
        # 6.x: el remove() de i2c devuelve void (y sin "return 0")
        def _fix_remove(m):
            body = m.group(3).replace("return 0;", "")
            return ("static void %s(struct i2c_client *%s)\n{%s\n}"
                    % (m.group(1), m.group(2), body))
        t = re.sub(r'static int (\w*remove)\(struct i2c_client \*(\w+)\)\n\{(.*?)\n\}',
                   _fix_remove, t, flags=re.S)
        # format string incompleto (Werror=format-extra-args)
        t = t.replace('"[spk_sw_gpio] prof index:",index',
                      '"[spk_sw_gpio] prof index:%d",index')
        # 5.10+: get_fs/set_fs/KERNEL_DS ya no existen
        t = t.replace('\tmm_segment_t fs;\n', '')
        t = t.replace('\tfs = get_fs();\n\tset_fs(KERNEL_DS);\n\n', '')
        t = t.replace('\tset_fs(fs);\n\n', '')
        t = t.replace('\tset_fs(fs);\n', '')
        # class_create() sin THIS_MODULE desde 6.4
        t = re.sub(r'class_create\(THIS_MODULE,\s*', 'class_create(', t)
        # el juego legacy de atributos de clase (struct class_attribute +
        # __ATTR() + class_create_file()) se deja como venia en 4.19: esa API
        # sigue existiendo en 6.6
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


def fix_class_attrs(root: Path) -> None:
    """6.6 exige la firma de device_attribute (struct device *, sin loff_t)."""
    for f in root.rglob("*.c"):
        text = f.read_text()
        orig = text
        # show: (struct class *class, struct device_attribute *attr, char *buf)
        text = re.sub(
            r"\(struct\s+class\s*\*class,\s*\n?\s*struct device_attribute \*attr, char \*buf\)",
            "(struct device *dev, struct device_attribute *attr, char *buf)",
            text,
        )
        # store: (struct class *class, struct device_attribute *attr, const char *buf, size_t len)
        text = re.sub(
            r"\(struct\s+class\s*\*class,\s*\n?\s*struct device_attribute \*attr,\s*\n?\s*const char \*buf, size_t len\)",
            "(struct device *dev, struct device_attribute *attr, const char *buf)",
            text,
        )
        if text != orig:
            f.write_text(text)
            print(f"[audio] firmas de device_attribute en {f.name}")


def fix_format_strings(root: Path) -> None:
    """7. %d con loff_t -> %lld (los size_t/loff_t de la API antigua)."""
    for f in root.rglob("*.c"):
        text = f.read_text()
        orig = text
        text = re.sub(r'"%d"\s*,\s*offset', '"%lld", offset', text)
        text = re.sub(r'"%d"\s*,\s*len\b', '"%zu", len', text)
        if text != orig:
            f.write_text(text)
            print(f"[audio] format strings en {f.name}")


def main() -> None:
    if not AW882XX.exists():
        raise SystemExit(f"falta {AW882XX}; descarga el arbol 4.19 de ruby")
    DST.mkdir(parents=True, exist_ok=True)
    port_aw882xx()
    port_haptic()
    fix_class_attrs(DST)
    fix_format_strings(DST)


if __name__ == "__main__":
    main()
