# 41 — Entorno real de pruebas

El host de este laboratorio **no es un PC**: es Arch Linux ARM (ruri) dentro
del propio Xiaomi ruby, con Android 17 en el slot A.

## Consecuencias

- `fastboot` del host no sirve para recuperar el teléfono.
- Si un experimento deja el dispositivo en bootloader, hace falta un PC con
  fastboot para recuperarlo.
- `termux` + APatch es el único acceso cómodo:
  `ssh termux 'su -c id'` → `uid=0(root)`.
- No se debe flashear un ramdisk/Android que no garantice retorno al slot A.

## Regla

1. Todo experimento de boot va al slot B con `tries=1`.
2. El initramfs debe tener watchdog y volver a A por sí solo.
3. Antes de flashear se guardan `boot_b` y `misc`.
4. Nunca probar un Android completo en B sin un mecanismo de retorno.
5. Los builds largos van a GitHub Actions; el host solo empaqueta y prueba.

## Estado actual

```
Android 17, slot A
sys.boot_completed=1
APatch root, superkey vacía
```

La prueba del ramdisk stock falló en `first_stage` por `modules.load` con
extensión `.ko`; el dispositivo volvió a A. La imagen corregida existe, pero
no se flashea hasta tener un retorno garantizado.
