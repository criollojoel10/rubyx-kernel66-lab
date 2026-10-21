# 44 — TEE real de ruby, APatch y bootloader spoof

## TEE de ruby

Ruby **no usa TEEGRIS**. Usa **Microtrust TEEI**:

```
ro.vendor.mtk_microtrust_tee_support = 1
/dev/teei_client
/dev/teei_config
/dev/teei_fp
/dev/tz_vfs
teei_daemon
android.hardware.keymaster@4.1-service.beanpod
vendor.mediatek.hardware.keymaster_attestation@1.1-service
vendor.microtrust.hardware.soter@1.0-service
```

El TEE no está dentro de `boot.img`:

- `boot.img` lleva kernel + ramdisk.
- El firmware TEE está en la partición `tee` / `tee_a` / `tee_b`.
- El driver TEE (Microtrust TEEI) va en el kernel o como módulo.
- El HAL keymaster/gatekeeper va en `/vendor`.

## Por qué falla el kernel A34

El 6.6 del A34 está configurado para **TEEGRIS**:

```
CONFIG_TEE=m
CONFIG_TEEGRIS_TEE_SUPPORT=m
# CONFIG_MICROTRUST_TEE_SUPPORT is not set
```

Ruby necesita Microtrust. Por eso el log de B dice:

```
keystore2 createOperation -1000
vold: decryptWithKeystoreKey failed
cryptfs init_user0 Failed
```

No es `/data` corrupta: el slot A sigue usando la misma `/data`. Es que el
kernel de prueba no expone `/dev/teei_client` ni el keymaster de Microtrust.

## APatch TEESimulator

El módulo se llama `teesim`:

```
name=TEESimulator
desc=Redirects key attestation for selected apps to an in-process reference KeyMint trusted application
```

Es un **redirect de attestation en userspace**, con `libteesim_keymint.so`,
`libteesim_keystore.so` y un daemon `teesim`. No crea un TEE real ni descifra
FBE. Puede afectar a apps que piden attestation, pero **no es la causa** del
fallo: el mismo fallo `init_user0` ocurrió con una imagen sin APatch.

## Bootloader spoof

El `lk`/`preloader` con `bldr_spoof` hace que el bootloader se presente como
locked. No aporta TEE, keymaster ni FBE; es ortogonal. Además:

- flashear `lk`/`preloader` es de alto riesgo;
- puede requerir factory reset;
- no arregla el fallo de `/data`;
- no debe hacerse para probar el kernel.

## Siguiente trabajo

Portar/compilar **Microtrust TEEI** para 6.6:

```
drivers/tee/teei/510  (o 400, según la versión de ruby)
CONFIG_MICROTRUST_TEE_SUPPORT=m
```

y cargarlo antes de keymaster:

```
tzdev -> gz_* / teei -> keymaster
```

Verificación en B:

```
ls -l /dev/teei_client /dev/teei_config
getprop | grep -i teei
ps -A | grep teei_daemon
dmesg | grep -i teei
```

Cuando aparezca `teei_daemon` y keymaster arranque, `init_user0` debería
funcionar. Formatear `/data` antes de eso solo perdería datos y no garantiza
nada.
