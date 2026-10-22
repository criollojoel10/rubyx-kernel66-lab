#!/usr/bin/env bash
# Port del audio de ruby: card MT6877 + altavoz aw882xx.
#
# La cadena de sonido de MT6877 (common, common_int, codec, mt6877 y
# audio_dsp) se compila EN EL ARBOL DE DEVICE MODULES: sus .ko estan en
# real_device_modules (mgk_64.bzl) y el build los genera con
# kernel_module(outs = ...) -> make -C $KERNEL_SRC M=<dir>. Copiarla al GKI
# seria duplicarla y romper el build (la common del GKI no tiene
# ../audio_dsp). Aqui solo se toca la card del arbol de device modules para
# anadirle el dai_link del altavoz, y se copian los headers mt-plat que usan
# los ports de carga y huella.
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

[ -d "$DM/sound/soc/mediatek/mt6877" ] || { echo "falta $DM" >&2; exit 1; }
[ -d "$GKI/include" ] || { echo "falta $GKI" >&2; exit 1; }

# 1) headers mt-plat que usan los ports (carga, huella, AFE)
if [ -d "$DM/drivers/misc/mediatek/include/mt-plat" ]; then
  mkdir -p "$GKI/include/mt-plat"
  cp -a "$DM/drivers/misc/mediatek/include/mt-plat/." "$GKI/include/mt-plat/"
  echo "[audio] include/mt-plat"
fi

# 1.5) IDs SMC de MTK que el audio del arbol de device modules necesita y
#      el header del GKI (KO common) no trae: solo usa MTK_SIP_AUDIO_CONTROL
#      (0x517) para el arranque del AFE. Sin el define, mt6877-afe-pcm.c y
#      mt6877-afe-clk.c no compilan. Se anade sin tocar los IDs del GKI.
SIP="$GKI/include/linux/soc/mediatek/mtk_sip_svc.h"
if [ -f "$SIP" ]; then
  python3 - "$SIP" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if "MTK_SIP_AUDIO_CONTROL" in t:
    print("[audio] mtk_sip_svc.h ya tiene MTK_SIP_AUDIO_CONTROL")
else:
    bloque = (
        "/* ruby: IDs SMC de MTK que el header del GKI no trae (audio MT6877) */\n"
        "#define MTK_SIP_AUDIO_CONTROL \\\n"
        "\tMTK_SIP_SMC_CMD(0x517)\n\n"
    )
    i = t.rfind("#endif")
    p.write_text(t[:i] + bloque + t[i:])
    print("[audio] MTK_SIP_AUDIO_CONTROL en mtk_sip_svc.h")
PY
fi

# 2) dai_link del altavoz aw882xx (del 4.19 de ruby) en la card 6.6
CARD="$DM/sound/soc/mediatek/mt6877/mt6877-mt6359.c"
[ -f "$CARD" ] || { echo "no existe $CARD" >&2; exit 1; }
if grep -q 'awinic_codecs' "$CARD"; then
  echo "[audio] el dai_link ya esta patcheado"
else
  python3 - "$CARD" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

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

# 2.1) el array, antes del primer dai_link
if "awinic_codecs" not in t:
    ancla = t.find("static struct snd_soc_dai_link mt6877_mt6359_dai_links[]")
    if ancla < 0:
        ancla = t.find("struct snd_soc_dai_link mt6877_mt6359_dai_links[]")
    if ancla < 0:
        sys.exit("no encuentro el dai_link de la card")
    t = t[:ancla] + BLOQUE + "\n" + t[ancla:]

# 2.2) en la funcion de dai_link: si hay altavoz aw882xx, se usan sus
#      codecs en vez de leerlos del DT (el DT de ruby no tiene
#      "mediatek,speaker-codec", tiene los nodos awinic,aw882xx_smartpa)
viejo = """\tspk_node = of_get_child_by_name(pdev->dev.of_node,
\t\t\t\t\t"mediatek,speaker-codec");"""
nuevo_bloque = """#if IS_ENABLED(CONFIG_SND_SMARTPA_AW882XX)
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
"""#if IS_ENABLED(CONFIG_SND_SMARTPA_AW882XX)
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
