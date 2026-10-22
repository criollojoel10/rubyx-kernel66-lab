# 46 — Requisitos Droidspaces (doc oficial) y baseline real

Fuente oficial: https://www.droidspaces.org/docs/kernel-configuration.html
(GKI 5.4+). El requirement checker instalado en el dispositivo es
`/data/local/Droidspaces/bin/droidspaces check` (módulo APatch `droidspaces`,
v7.0.0, daemon ya arranca en boot).

## Lo que exige la doc oficial en GKI

1. Parche kABI **obligatorio** (sin él, bootloop):
   `kernel-patches/GKI/below-kernel-6.12/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch`
   (si el dispositivo entra en bootloop, probar las alternativas 3_4_5 y 1_2_3,
   que usan otros slots de padding).
2. Editar `arch/arm64/configs/gki_defconfig` **en el sitio** (no fragmento):
   `SYSVIPC`, `POSIX_MQUEUE`, `IPC_NS`, `PID_NS`, `DEVTMPFS`,
   `NETFILTER_XT_MATCH_ADDRTYPE`; opcionales: `USER_NS`, `IP6_NF_NAT`,
   `IP6_NF_TARGET_MASQUERADE`, `MACVLAN`, `NETFILTER_XT_TARGET_REJECT/LOG`,
   `NETFILTER_XT_MATCH_RECENT`, `IP_SET*`, `NETFILTER_XT_SET`,
   `TMPFS_POSIX_ACL`, `TMPFS_XATTR`.
3. `CONFIG_CFS_BANDWIDTH` y `CONFIG_CGROUP_PIDS` **deben quedar comentadas**:
   redimensionan scheduler/cgroup, cambian el CRC de miles de símbolos y
   rompen los módulos de vendor. Solo se pueden activar reconstruyendo
   todos los módulos y flasheando vendor_boot + vendor_dlkm + system_dlkm a la vez.
4. Root: KernelSU recomendado; Magisk y APatch también valen, pero su shell
   lleva filtro seccomp: el backend debe correr como **daemon arrancado en boot**,
   no desde una shell interactiva. En ruby esto ya está cubierto por el módulo
   APatch `droidspaces` (daemon activo al boot).

## Baseline real (kernel stock 6.6 de ruby, slot A)

`docs/evidence/droidspaces-check-stock-2026-10-22.txt`:

```
MUST HAVE
  [✓] Root privileges        [✓] Mount namespace      [✓] pivot_root
  [✓] Linux version          [✓] UTS namespace        [✓] /proc, /sys
  [✗] PID namespace          [✗] IPC namespace        [✓] Seccomp
  => 2 requisitos obligatorios faltan

OPTIONAL que faltan
  [✗] Macvlan support                  (CONFIG_MACVLAN)
  [✗] IPv6 NAT support                 (CONFIG_IP6_NF_NAT, CONFIG_IP6_NF_TARGET_MASQUERADE)
  [✗] CPU limit support                (CONFIG_CFS_BANDWIDTH) -> --cpus desactivado
  [✗] Process limit support            (CONFIG_CGROUP_PIDS)  -> --pids-limit desactivado
  [✗] Sandboxing (user namespaces)     (CONFIG_USER_NS)
```

## Plan para nuestro kernel 6.6

- `scripts/apply-droidspaces-kabi.sh` aplica el parche kABI oficial
  (variantes 6_7_8 -> 3_4_5 -> 1_2_3) sobre el core `kernel-6.6`.
- `configs/ruby-6.6/droidspaces-gki.fragment` = lista oficial GKI.
- `scripts/patch-gki-core.sh` las escribe en `gki_defconfig`.
- `scripts/check-kabi.py` compara los CRC de `Module.symvers` contra la
  baseline (`configs/ruby-6.6/kabi-baseline.symvers.gz`): si el parche kABI
  funciona, **ningún CRC existente puede cambiar**.
- CI: `build-ruby-droidspaces-kabi.yml` (con parche) y
  `build-ruby-droidspaces.yml` (subconjunto sin opciones rompientes).

## Objetivo

Que `droidspaces check` pase de "2 required missing" a 0, mantendo kABI
intacto. `--cpus` y `--pids-limit` quedan en gris (aceptado por la doc
oficial); el resto de funciones debe quedar completo.
