#!/usr/bin/env bash
# Aplica el piloto pinctrl-mt6877 a un kernel-6.6 ya clonado.
# Uso: ./port/pinctrl/apply.sh /ruta/a/kernel-6.6
set -euo pipefail
K="$(realpath -m "${1:?falta la ruta del kernel-6.6}")"
cd "$(dirname "$0")"
D="$K/drivers/pinctrl/mediatek"
[ -d "$D" ] || { echo "no existe $D" >&2; exit 1; }

cp pinctrl-mt6877.c pinctrl-mtk-mt6877.h "$D/"
patch -p1 -d "$K" < 0001-pinctrl-paris-mt6877.patch

if ! grep -q '^config PINCTRL_MT6877$' "$D/Kconfig"; then
  cat Kconfig.fragment >> "$D/Kconfig"
fi
if ! grep -q 'pinctrl-mt6877.o' "$D/Makefile"; then
  cat Makefile.fragment >> "$D/Makefile"
fi

echo "pinctrl-mt6877 aplicado en $D"
