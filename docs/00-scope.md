# 00 — Alcance

## Objetivo

Construir un kernel 6.6 para Xiaomi ruby (MT6877V) con:

- base MTK 6.6 del Galaxy A34 (a34x);
- especificación de hardware del árbol 4.19 de RubyxLabs;
- núcleo Android común ACK `android15-6.6`;
- Droidspaces como propiedad nativa desde el primer defconfig.

## Hito actual

**Hito 1:** compilar sin modificaciones el A34 6.6.127 y demostrar que el
entorno, el toolchain y el procedimiento son reproducibles.

## No objetivos de esta etapa

- No se porta código de ruby.
- No se parchean drivers para “hacer que compile”.
- No se flashea nada.
- No se declara un build reproducible sin una segunda compilación limpia.
- No se sustituyen fuentes por artefactos binarios.

## Oráculos que se congelarán después del Hito 1

| Oráculo | Fuente |
|---|---|
| A | Kernel 4.19 funcional de ruby (fuentes + artefactos) |
| B | Árbol 4.19 de RubyxLabs |
| C | Este build de referencia A34 6.6.127 |
| D | Kernel 6.6 ya publicado por RubyxLabs (binario) |
