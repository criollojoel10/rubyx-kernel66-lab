#!/usr/bin/env bash
# MFD mt6397 (PMIC mt6359p): IRQ del PMIC no fatal.
#
# mt6397_probe() -> mt6358_irq_init() hace devm_request_threaded_irq() sobre
# el IRQ del PMIC (irq=61, resuelto via interrupt-parent=<pio/pinctrl>) y, si
# falla, devuelve el error y aborta TODO el probe del MFD:
#
#   mt6397 10026000.pwrap:mt6359-pmic: Failed to register IRQ=61, ret=-38
#   mt6397: probe of 10026000.pwrap:mt6359-pmic failed with error -38
#
# Sin el probe del MFD no se crean las celdas mt6359p-* (regulator, keys,
# rtc, ...), asi que mt6359p-regulator nunca registra vcc/vccq/vccq2 y el UFS
# 11270000.ufshci queda con "vcc get failed -517" para siempre: sin UFS no
# aparecen super/metadata/boot_b/vbmeta_b y Android init muere con
# InitFatalReboot (signal 6).
#
# El fallo es -ENOSYS (el irq_chip del EINT/pinctrl no expone irq_set_type a
# tiempo; hay una carrera con la carga de pinctrl-mt6877 que mtk_wdt.ko puso
# de manifiesto). Para el arranque basta con que el MFD siga adelante: las
# celdas se crean, mt6359p-regulator registra los reguladores y el UFS sondea.
# Las sub-IRQ del PMIC (teclas/cargador/bateria) no dispararan hasta que se
# arregle la carrera; eso es milestone 3/4, no bloquea el boot.
#
# Se hace no fatal SOLO el fallo de request_threaded_irq (se conserva el
# irq_domain ya creado, necesario para mapear las sub-IRQ de las celdas).
#
# Uso: ./port/mfd/apply.sh [raiz/del/arbol]
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${1:-}" ]; then
  DM="$1/kernel/kernel_device_modules-6.6"
else
  DM="sources/a34x/kernel/kernel_device_modules-6.6"
fi

F="$DM/drivers/mfd/mt6358-irq.c"
[ -f "$F" ] || { echo "falta $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import sys

p = sys.argv[1]
s = open(p).read()

MARKER = "RUBY_NONFATAL_PMIC_IRQ"
if MARKER in s:
    print("  mt6358-irq.c: IRQ del PMIC ya es no fatal")
    sys.exit(0)

anchor = '''	if (ret) {
		dev_err(chip->dev, "Failed to register IRQ=%d, ret=%d\\n",
			chip->irq, ret);
		return ret;
	}

	enable_irq_wake(chip->irq);
'''
assert anchor in s, "no encuentro el bloque request_threaded_irq de mt6358_irq_init"

replacement = '''	if (ret) {
		dev_err(chip->dev,
			"Failed to register IRQ=%d, ret=%d (continuing, RUBY_NONFATAL_PMIC_IRQ)\\n",
			chip->irq, ret);
		/* No abortar el probe del MFD: sin las celdas mt6359p-* el UFS
		 * (que pide vcc/vccq/vccq2 de mt6359p-regulator) queda en -517
		 * para siempre y Android init muere (InitFatalReboot). Las sub-IRQ
		 * del PMIC no disparan hasta arreglar la carrera con pinctrl.
		 */
		return 0;
	}

	enable_irq_wake(chip->irq);
'''
s = s.replace(anchor, replacement, 1)
open(p, 'w').write(s)
print("  mt6358-irq.c: fallo de request_threaded_irq hecho no fatal")
PY
