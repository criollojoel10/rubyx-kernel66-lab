#!/usr/bin/env bash
# Muestra el error clave de un run de CI (sin ruido de bazel/clang).
# Uso: scripts/ci-error.sh <run-id> [lineas]
set -uo pipefail
export HOME=/root
cd "$(dirname "$0")/.."

RUN="${1:?falta el run}"
N="${2:-12}"

gh run view -R criollojoel10/rubyx-kernel66-lab "$RUN" --log-failed 2>/dev/null \
 | sed 's/^[^\t]*\t[^\t]*\t[0-9T:.Z-]*\t//' \
 | grep -E 'ERROR|No rule to make|Error 1|Error 2|error:|fatal error|undefined reference|No such file|Unable to find|New value: # CONFIG' \
 | grep -vE 'include/llvm|filesystem_error|format_error|system_error|ErrorHandler|pyerrors|distutils|rich/errors|setuptools|urllib|__error|ErrorHandling|CXError' \
 | tail -"$N" | cut -c1-400
