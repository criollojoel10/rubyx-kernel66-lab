#!/usr/bin/env bash
# Copia al GKI los drivers que necesita ruby y que en el arbol del A34 viven
# en los device modules:
#
#   drivers/tee/teei/400/            -> Microtrust TEEI 400 (el TEE de ruby)
#   drivers/gpu/drm/mediatek/mediatek_v2/ -> API de display v2 (la que usan el
#                                            panel m16 y el tactil FT3680 del
#                                            GKI, que son de Samsung)
#
# Se compilan built-in (=y) dentro del GKI, igual que en el kernel stock de
# ruby (que lleva todos los drivers de MTK built-in).
#
# Uso: ./port/mtk-drivers/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  GKI="$1/kernel-6.6"
  DM="$1/kernel/kernel_device_modules-6.6"
else
  GKI="sources/a34x/kernel-6.6"
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

# --- 1) TEEI 400 (Microtrust) ----------------------------------------------
if [ -d "$DM/drivers/tee/teei/400" ]; then
  rm -rf "$GKI/drivers/tee/teei"
  mkdir -p "$GKI/drivers/tee/teei"
  cp -a "$DM/drivers/tee/teei/400" "$GKI/drivers/tee/teei/400"
  cp "$DM/drivers/tee/teei/Makefile.include" "$GKI/drivers/tee/teei/" 2>/dev/null || true
  cat > "$GKI/drivers/tee/teei/Makefile" <<'EOF'
# Microtrust TEEI: el TEE real de ruby (el A34 usa TEEGRIS de Samsung).
obj-$(CONFIG_MICROTRUST_TEE_SUPPORT) += $(subst ",,$(CONFIG_MICROTRUST_TEE_VERSION))/
EOF
  K="$GKI/drivers/tee/Makefile"
  grep -q 'CONFIG_MICROTRUST_TEE_SUPPORT' "$K" ||
    echo 'obj-$(CONFIG_MICROTRUST_TEE_SUPPORT) += teei/' >> "$K"
  echo "[mtk-drivers] TEEI 400 copiado al GKI"
fi

# --- 2) mediatek_v2 (display v2) -------------------------------------------
if [ -d "$DM/drivers/gpu/drm/mediatek/mediatek_v2" ]; then
  mkdir -p "$GKI/drivers/gpu/drm/mediatek"
  rm -rf "$GKI/drivers/gpu/drm/mediatek/mediatek_v2"
  cp -a "$DM/drivers/gpu/drm/mediatek/mediatek_v2" \
        "$GKI/drivers/gpu/drm/mediatek/mediatek_v2"
  M="$GKI/drivers/gpu/drm/mediatek/Makefile"
  grep -q 'mediatek_v2/' "$M" ||
    echo 'obj-$(CONFIG_DRM_MEDIATEK_V2) += mediatek_v2/' >> "$M"
  # El GKI de A34 usa la v1 (mi_disp) y no sourcea la v2: hay que engancharla.
  # kconfig resuelve los "source" relativos contra el cwd (la raiz del
  # package), no contra el directorio del Kconfig que lo contiene: por eso
  # el path es relativo y hace falta el symlink de abajo.
  grep -q 'mediatek_v2/Kconfig' "$K" ||
    echo 'source "mediatek_v2/Kconfig"' >> "$K"
  # kconfig resuelve los "source" relativos contra el cwd (la raiz del
  # package), no contra el directorio del Kconfig que lo contiene: por eso
  # el GKI de A34 sourcea "mediatek_v2/Kconfig" y hace falta el symlink.
  ln -sfn drivers/gpu/drm/mediatek/mediatek_v2 "$GKI/mediatek_v2"
  ln -sfn drivers/gpu/drm/mediatek/mediatek_v2 "$DM/mediatek_v2"
  K="$GKI/drivers/gpu/drm/mediatek/Kconfig"
  echo "[mtk-drivers] mediatek_v2 copiada al GKI"
fi

# 3) cabeceros UAPI de MTK (los usa la mediatek_v2 y el panel m16) --------
# El GKI del A34 no los tiene; estan en los device modules.
for h in include/uapi/drm/mediatek_drm.h \
         include/linux/soc/mediatek/mtk-cmdq-ext.h \
         include/linux/mailbox/mtk-cmdq-mailbox-ext.h; do
  if [ -f "$DM/$h" ]; then
    mkdir -p "$GKI/$(dirname "$h")"
    cp -a "$DM/$h" "$GKI/$h"
    echo "[mtk-drivers] $h copiado al GKI"
  fi
done

echo "[mtk-drivers] listo"
