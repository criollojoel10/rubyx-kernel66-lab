#!/usr/bin/env bash
# Aplica el altavoz (Awinic aw882xx) y el vibrador (aw8697) de ruby al GKI 6.6.
#
# El 4.19 de ruby los trae en:
#   sound/soc/codecs/aw882xx/         (altavoz, ASoC component)
#   drivers/input/misc/aw8697_haptic/ (vibrador)
#
# Uso: ./port/audio/apply.sh [ruta/al/GKI]
set -euo pipefail
cd "$(dirname "$0")/../.."

GKI="${1:-sources/a34x/kernel-6.6}"
[ -d "$GKI/sound/soc/codecs" ] || { echo "no existe $GKI/sound/soc/codecs" >&2; exit 1; }
[ -d "$GKI/drivers/input/misc" ] || { echo "no existe $GKI/drivers/input/misc" >&2; exit 1; }

SRC="port/audio"
[ -d "$SRC/aw882xx" ] || { echo "falta $SRC/aw882xx; ejecuta scripts/port-audio-aw882xx.py" >&2; exit 1; }

# --- altavoz --------------------------------------------------------------
rm -rf "$GKI/sound/soc/codecs/aw882xx"
cp -a "$SRC/aw882xx" "$GKI/sound/soc/codecs/aw882xx"

KC="$GKI/sound/soc/codecs/Kconfig"
if [ -f "$KC" ] && ! grep -q 'aw882xx/Kconfig' "$KC"; then
  echo 'source "aw882xx/Kconfig"' >> "$KC"
fi
MK="$GKI/sound/soc/codecs/Makefile"
if [ -f "$MK" ] && ! grep -q 'aw882xx/' "$MK"; then
  echo 'obj-$(CONFIG_SND_SOC_AW882XX) += aw882xx/' >> "$MK"
fi
if [ ! -f "$GKI/sound/soc/codecs/aw882xx/Kconfig" ]; then
  cat > "$GKI/sound/soc/codecs/aw882xx/Kconfig" <<'EOF'
config SND_SOC_AW882XX
	tristate "Awinic AW882XX smart amplifier"
	depends on I2C
	select SND_SOC_COMPONENT
	help
	  Driver del altavoz (Awinic AW882xx) del Xiaomi ruby.
EOF
fi

# --- vibrador -------------------------------------------------------------
rm -rf "$GKI/drivers/input/misc/aw8697_haptic"
cp -a "$SRC/aw8697_haptic" "$GKI/drivers/input/misc/aw8697_haptic"

if [ -f "$GKI/drivers/input/misc/Kconfig" ] && ! grep -q 'aw8697_haptic' "$GKI/drivers/input/misc/Kconfig"; then
  cat >> "$GKI/drivers/input/misc/Kconfig" <<'EOF'

config DRIVER_AW8697
	tristate "AW8697 haptic driver"
	help
	  Driver del motor de vibracion (Awinic AW8697) del Xiaomi ruby.
EOF
fi
if [ -f "$GKI/drivers/input/misc/Makefile" ] && ! grep -q 'aw8697_haptic' "$GKI/drivers/input/misc/Makefile"; then
  echo 'obj-$(CONFIG_DRIVER_AW8697) += aw8697_haptic/' >> "$GKI/drivers/input/misc/Makefile"
fi

echo "[audio] altavoz y vibrador aplicados en $GKI"
