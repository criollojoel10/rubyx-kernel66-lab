#!/usr/bin/env bash
# Port del audio de ruby: la card MT6877 (6.6) + el altavoz aw882xx.
#
# La card de sonido de MT6877 vive en los device modules, que NO se compilan
# (CONFIG_DEVICE_MODULES_ALLOW_BUILTIN=n), asi que hay que copiarla al GKI.
# Ademas la version 6.6 de la card no conoce el altavoz: el dai_link del
# aw882xx se trae del 4.19 de ruby.
#
# Uso: ./port/audio/apply-card.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  GKI="$1/kernel-6.6"
  DM="$1/kernel/kernel_device_modules-6.6"
else
  GKI="sources/a34x/kernel-6.6"
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

[ -d "$GKI/sound/soc/mediatek" ] || { echo "falta $GKI" >&2; exit 1; }
[ -d "$DM/sound/soc/mediatek/mt6877" ] || { echo "falta $DM" >&2; exit 1; }

echo "[audio] copiando la cadena de sonido de MT6877 al GKI"

# 1) la card y sus sisters
for d in mt6877 common_int codec; do
  [ -d "$DM/sound/soc/mediatek/$d" ] || continue
  rm -rf "$GKI/sound/soc/mediatek/$d"
  cp -a "$DM/sound/soc/mediatek/$d" "$GKI/sound/soc/mediatek/$d"
  echo "   sound/soc/mediatek/$d"
done

# 2) common: se sustituye ENTERA por la de los device modules. La version del
#    GKI es la upstream y no sirve para la card: le faltan use_dram_only,
#    using_sram, ack(), mtk_sp_*, mtk_audio_sram_*... (el stock tampoco compila
#    la common del GKI: su config no tiene CONFIG_SND_SOC_MEDIATEK).
if [ -d "$DM/sound/soc/mediatek/common" ]; then
  rm -rf "$GKI/sound/soc/mediatek/common"
  cp -a "$DM/sound/soc/mediatek/common" "$GKI/sound/soc/mediatek/common"
  echo "   sound/soc/mediatek/common"

  # El Makefile vendor usa CONFIG_DEVICE_MODULES_* y DEVICE_MODULES_PATH, que
  # no existen en la config del GKI: se reescribe con simbolos del GKI y con
  # los objetos que la card necesita siempre.
  cat > "$GKI/sound/soc/mediatek/common/Makefile" <<'EOF'
# ruby: common de los device modules, adaptada al GKI
# (los simbolos CONFIG_DEVICE_MODULES_* no existen fuera del arbol vendor)
obj-$(CONFIG_SND_SOC_MEDIATEK) += snd-soc-mtk-common.o
snd-soc-mtk-common-objs := mtk-afe-platform-driver.o mtk-afe-fe-dai.o \
			   mtk-mmap-ion.o mtk-usb-offload-ops.o \
			   mtk-sram-manager.o mtk-sp-pcm-ops.o mtk-afe-debug.o
obj-$(CONFIG_SND_SOC_MEDIATEK) += mtk-afe-external.o mtk-sp-spk-amp.o
EOF

  # el header de los device modules no define MTK_SIP_AUDIO_CONTROL, pero la
  # AFE de mt6877 lo usa (SMC 0x517); el header del GKI si lo tenia.
  python3 - "$GKI/sound/soc/mediatek/common/mtk-base-afe.h" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if "MTK_SIP_AUDIO_CONTROL" not in t:
    ancla = "#define MTK_STREAM_NUM"
    if ancla not in t:
        sys.exit(f"falta '{ancla}' en {p}")
    t = t.replace(ancla,
                  "#include <linux/soc/mediatek/mtk_sip_svc.h>\n"
                  "#define MTK_SIP_AUDIO_CONTROL MTK_SIP_SMC_CMD(0x517)\n\n"
                  + ancla, 1)
    p.write_text(t)
    print("   mtk-base-afe.h: MTK_SIP_AUDIO_CONTROL")
PY
fi

# 3) headers mt-plat que usa la AFE
if [ -d "$DM/drivers/misc/mediatek/include/mt-plat" ]; then
  mkdir -p "$GKI/include/mt-plat"
  cp -a "$DM/drivers/misc/mediatek/include/mt-plat/." "$GKI/include/mt-plat/"
  echo "   include/mt-plat"
fi

# 4) dai_link del altavoz aw882xx (del 4.19 de ruby) en la card 6.6
CARD="$GKI/sound/soc/mediatek/mt6877/mt6877-mt6359.c"
if [ -f "$CARD" ] && ! grep -q 'awinic_codecs' "$CARD"; then
  python3 - "$CARD" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# el simbolo del codec es de los device modules y el GKI no lo conoce: se usa
# el de la propia card, que si esta en la config del GKI
t = t.replace("#if IS_ENABLED(CONFIG_DEVICE_MODULES_SND_SOC_MT6359P)",
              "#if IS_ENABLED(CONFIG_SND_SOC_MT6877_MT6359P)")

BLOQUE = '''/* ruby: altavoz aw882xx (dos chips: 0x34 y 0x35) */
struct snd_soc_dai_link_component awinic_codecs[] = {
	{
		.of_node = NULL,
		.dai_name = "aw882xx-aif-7-34",
		.name = "aw882xx_smartpa.7-0034",
	},
	{
		.of_node = NULL,
		.dai_name = "aw882xx-aif-7-35",
		.name = "aw882xx_smartpa.7-0035",
	},
};
'''

# 4.1) el array, antes del primer dai_link
if "struct snd_soc_dai_link_component" not in t:
    ancla = t.find("static struct snd_soc_dai_link mt6877_mt6359_dai_links[]")
    if ancla < 0:
        ancla = t.find("struct snd_soc_dai_link mt6877_mt6359_dai_links[]")
    if ancla < 0:
        sys.exit("no encuentro el dai_link de la card")
    t = t[:ancla] + BLOQUE + "\n" + t[ancla:]

# 4.2) en la funcion de dai_link: si hay altavoz aw882xx, se usan sus
#      codecs en vez de leerlos del DT (el DT de ruby no tiene
#      "mediatek,speaker-codec", tiene los nodos awinic,aw882xx_smartpa)
viejo = """\tspk_node = of_get_child_by_name(pdev->dev.of_node,
\t\t\t\t\t"mediatek,speaker-codec");"""
nuevo_bloque = """#ifdef CONFIG_SND_SMARTPA_AW882XX
\t{
\t\tstruct snd_soc_dai_link *dl;

\t\tfor_each_card_prelinks(card, i, dl) {
\t\t\tif (!dl->platforms->name)
\t\t\t\tdl->platforms->of_node = platform_node;
\t\t\tif (!strcmp(dl->name, "Speaker Codec") ||
\t\t\t    !strcmp(dl->name, "Speaker Codec Ref")) {
\t\t\t\tdl->codecs = awinic_codecs;
\t\t\t\tdl->num_codecs = ARRAY_SIZE(awinic_codecs);
\t\t\t}
\t\t}
\t\tgoto skip_spk_node;
\t}
#endif
\tspk_node = of_get_child_by_name(pdev->dev.of_node,
\t\t\t\t\t"mediatek,speaker-codec");"""
if "skip_spk_node" in t:
    print("[audio] el dai_link ya esta patcheado")
elif viejo in t:
    t = t.replace(viejo, nuevo_bloque, 1)
    # la etiqueta va DESPUES del bucle que llama a
    # snd_soc_of_get_dai_link_codecs(): esa funcion reserva dai_link->codecs
    # por su cuenta, asi que el bucle tiene que saltarse entero cuando
    # usamos los codecs del aw882xx (si no, pisa los nuestros y ademas
    # usa un spk_node sin inicializar)
    ancla_dev = "\tcard->dev = &pdev->dev;"
    if t.count(ancla_dev) != 1:
        sys.exit("no encuentro 'card->dev = &pdev->dev;' (o no es unico); "
                 "sin el ancla no se puede poner skip_spk_node")
    t = t.replace(ancla_dev,
"""#ifdef CONFIG_SND_SMARTPA_AW882XX
skip_spk_node:
#endif
\tcard->dev = &pdev->dev;""", 1)
    print("[audio] dai_link del aw882xx anadido")
else:
    print("[audio] AVISO: no encuentro el bloque del spk_node; el altavoz "
          "quedara sin dai_link")

p.write_text(t)
PY
fi

# 5) Kconfig del GKI: la card necesita la common (CONFIG_SND_SOC_MEDIATEK,
#    que es un tristate oculto: solo se activa con select) y los dos helpers.
K="$GKI/sound/soc/mediatek/Kconfig"
if [ -f "$K" ]; then
  python3 - "$K" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

BLOQUE = '''config SND_SOC_MT6877
\ttristate "ASoC support for Mediatek MT6877 chip"
\tdepends on ARCH_MEDIATEK
\tselect SND_SOC_MEDIATEK
\thelp
\t  This adds ASoC driver for Mediatek MT6877 boards
\t  that can be used with other codecs.

config SND_SOC_MT6877_MT6359P
\ttristate "ASoc Audio driver for MT6877 with MT6359P codec"
\tdepends on SND_SOC_MT6877
\thelp
\t  This adds ASoC driver for MT6877 boards
\t  with the MT6359P codecs.
'''

# idempotente: se quitan las definiciones previas y se pone la canonica
for sym in ("SND_SOC_MT6877", "SND_SOC_MT6877_MT6359P"):
    t = re.sub(r"(?ms)^config %s\n(?:\t.*\n|\n)*" % sym, "", t)

p.write_text(t.rstrip("\n") + "\n\n" + BLOQUE)
print("   Kconfig: SND_SOC_MT6877 (+ select SND_SOC_MEDIATEK)")
PY
fi

# 5b) codec MT6359P: el driver de los device modules. El del GKI es el
#     upstream y depende de MTK_PMIC_WRAP, que esta apagado.
CODECS="$GKI/sound/soc/codecs"
if [ -d "$DM/sound/soc/codecs" ] && [ -d "$CODECS" ]; then
  for f in mt6359.c mt6359.h mt6359p.h mt6359p-accdet.c mt6359p-accdet.h; do
    [ -f "$DM/sound/soc/codecs/$f" ] && cp -a "$DM/sound/soc/codecs/$f" "$CODECS/$f"
  done
  # accdet (deteccion de auricular) solo si el config lo pide; si no, no entra
  if ! grep -q 'snd-soc-mt6359p-accdet-o' "$CODECS/Makefile" 2>/dev/null; then
    printf '%s\n%s\n' \
      'obj-$(CONFIG_SND_SOC_MT6359P_ACCDET) += snd-soc-mt6359p-accdet.o' \
      'snd-soc-mt6359p-accdet-objs := mt6359p-accdet.o' >> "$CODECS/Makefile"
  fi
  # el codigo vendor incluye su cabecera privada solo si esta el simbolo de
  # los device modules; en el GKI ese simbolo no existe, asi que se incluye
  # siempre (el codec solo se compila con la card, ver Makefile)
  python3 - "$CODECS/mt6359.c" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
viejo = """#if IS_ENABLED(CONFIG_DEVICE_MODULES_SND_SOC_MT6359P)
#include "mt6359p.h"
#elif IS_ENABLED(CONFIG_DEVICE_MODULES_SND_SOC_MT6359)
#include "mt6359.h"
#endif"""
cambiado = False
if viejo in t:
    t = t.replace(viejo, '#include "mt6359p.h"', 1)
    cambiado = True
    print("   mt6359.c: include de mt6359p.h")
if "ruby: el MFD mt6397" not in t:
    ancla = '#include "mt6359p.h"'
    if ancla not in t:
        sys.exit("mt6359.c: no encuentro el include de mt6359p.h")
    extra = "\n".join([
        '#include "mt6359p.h"',
        '',
        '/* ruby: el MFD mt6397 de 6.6 crea el device "mt6359-sound" (celda sin',
        ' * of_compatible), asi que el driver tiene que declararse con ese nombre;',
        ' * si no, el codec nunca sondea y no hay sound card. */',
        '#undef DEVICE_MT6359_NAME',
        '#define DEVICE_MT6359_NAME "mt6359-sound"',
        '',
    ])
    t = t.replace(ancla, extra, 1)
    cambiado = True
    print("   mt6359.c: device name mt6359-sound (MFD mt6397)")
if cambiado:
    p.write_text(t)
PY
  python3 - "$CODECS/Makefile" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
linea = "obj-$(CONFIG_SND_SOC_MT6877_MT6359P)\t+= snd-soc-mt6359.o\n"
# quitar cualquier variante previa (incluida la del simbolo vendor)
t = "".join(l for l in t.splitlines(keepends=True)
            if "snd-soc-mt6359.o" not in l)
t = t.rstrip("\n") + "\n" + linea
p.write_text(t)
print("   sound/soc/codecs/Makefile: snd-soc-mt6359.o")
PY
  echo "   sound/soc/codecs/mt6359 (vendor)"
fi

M="$GKI/sound/soc/mediatek/Makefile"
if [ -f "$M" ] && ! grep -q 'mt6877/' "$M"; then
  cat >> "$M" <<'EOF'
obj-$(CONFIG_SND_SOC_MT6877) += mt6877/
EOF
  echo "   Makefile: mt6877/"
fi

# 6) el codigo del altavoz (port en port/audio/aw882xx)
if [ -d "port/audio/aw882xx" ]; then
  rm -rf "$GKI/sound/soc/codecs/aw882xx"
  mkdir -p "$GKI/sound/soc/codecs"
  cp -a "port/audio/aw882xx" "$GKI/sound/soc/codecs/aw882xx"
  KC="$GKI/sound/soc/codecs/Kconfig"
  [ -f "$KC" ] || : > "$KC"
  grep -q 'aw882xx/Kconfig' "$KC" || \
    echo 'source "sound/soc/codecs/aw882xx/Kconfig"' >> "$KC"
  MK="$GKI/sound/soc/codecs/Makefile"
  [ -f "$MK" ] || : > "$MK"
  grep -q 'aw882xx/' "$MK" || \
    echo 'obj-$(CONFIG_SND_SMARTPA_AW882XX) += aw882xx/' >> "$MK"
  echo "   sound/soc/codecs/aw882xx"
fi

echo "[audio] card MT6877 lista en el GKI"
