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

# 2) common: el GKI tiene su version; se fusiona la de los device modules
#    (mtk-sp-spk-amp.h, mtk-afe-external.c, mtk-sram-manager.c...)
if [ -d "$DM/sound/soc/mediatek/common" ]; then
  for f in "$DM/sound/soc/mediatek/common"/*; do
    b="$(basename "$f")"
    [ -e "$GKI/sound/soc/mediatek/common/$b" ] && continue
    cp -a "$f" "$GKI/sound/soc/mediatek/common/$b"
  done
  echo "   sound/soc/mediatek/common (ficheros que faltaban)"
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
    t = t.replace("""\tfor_each_card_prelinks(card, i, dai_link) {
\t\tif (!dai_link->platforms->name)""",
"""#ifdef CONFIG_SND_SMARTPA_AW882XX
skip_spk_node:
#endif
\tfor_each_card_prelinks(card, i, dai_link) {
\t\tif (!dai_link->platforms->name)""", 1)
    print("[audio] dai_link del aw882xx anadido")
else:
    print("[audio] AVISO: no encuentro el bloque del spk_node; el altavoz "
          "quedara sin dai_link")

p.write_text(t)
PY
fi

# 5) Kconfig y Makefile del GKI
K="$GKI/sound/soc/mediatek/Kconfig"
if [ -f "$K" ] && ! grep -q 'SND_SOC_MT6877$' "$K"; then
  cat >> "$K" <<'EOF'

config SND_SOC_MT6877
	tristate "ASoC support for Mediatek MT6877 chip"
	depends on ARCH_MEDIATEK
	select SND_SOC_MTK_SRAM
	select SND_SOC_MTK_SMART_PHONE
	help
	  This adds ASoC driver for Mediatek MT6877 boards
	  that can be used with other codecs.

config SND_SOC_MT6877_MT6359P
	tristate "ASoc Audio driver for MT6877 with MT6359P codec"
	depends on SND_SOC_MT6877
	help
	  This adds ASoC driver for MT6877 boards
	  with the MT6359P codecs.
EOF
  echo "   Kconfig: SND_SOC_MT6877"
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
