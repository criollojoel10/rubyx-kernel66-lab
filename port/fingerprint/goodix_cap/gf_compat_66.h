/*
 * Compatibilidad del port goodix_cap (4.19 -> 6.6).
 *
 * El driver venia del arbol 4.19 de ruby y usaba dos cosas que el GKI no
 * tiene:
 *
 *  - la HAL mtk_spi (struct mt_chip_conf y los enums SPI_CPOL/SPI_MSB y
 *    FIFO_TRANSFER, DMA_TRANSFER).
 *    En 6.6 el driver SPI estandar configura el clock y el modo, asi que
 *    la estructura solo sobrevive porque el ioctl de configuracion la
 *    guarda en gf_dev->spi_mcc; no se programa ningun registro.
 *
 *  - el notifier de mi_disp (FOD/AOD), que es un driver de Xiaomi que no
 *    esta en el arbol. Sin el, la huella funciona con la pantalla
 *    encendida; el desbloqueo en AOD no recibira los eventos de DPMS.
 */
#ifndef __GF_COMPAT_66_H
#define __GF_COMPAT_66_H

#include <linux/types.h>
#include <linux/notifier.h>

struct mt_chip_conf {
	unsigned int setuptime;
	unsigned int holdtime;
	unsigned int high_time;
	unsigned int low_time;
	unsigned int cs_idletime;
	unsigned int ulthgh_thrsh;
	unsigned int cpol;
	unsigned int cpha;
	unsigned int rx_mlsb;
	unsigned int tx_mlsb;
	unsigned int tx_endian;
	unsigned int rx_endian;
	unsigned int com_mod;
	unsigned int pause;
	unsigned int finish_intr;
	unsigned int deassert;
	unsigned int ulthigh;
	unsigned int tckdly;
};

enum spi_transfer_mode {
	SPI_DMA_TRANSFER_MODE = 1,
	SPI_FIFO_TRANSFER_MODE = 0,
};

#define SPI_CPOL_0	0
#define SPI_CPHA_0	0
#define SPI_MSB		1
#define SPI_LENDIAN	0
#define FIFO_TRANSFER	SPI_FIFO_TRANSFER_MODE
#define DMA_TRANSFER	SPI_DMA_TRANSFER_MODE

/* eventos de mi_disp que usa el notifier de fb (FOD/AOD) */
#define MI_DISP_DPMS_EVENT		0x01
#define MI_DISP_DPMS_EARLY_EVENT	0x02
enum {
	MI_DISP_DPMS_ON = 0,
	MI_DISP_DPMS_LP1 = 1,
	MI_DISP_DPMS_LP2 = 2,
	MI_DISP_DPMS_STANDBY = 3,
	MI_DISP_DPMS_SUSPEND = 4,
	MI_DISP_DPMS_POWERDOWN = 5,
};

static inline int mi_disp_register_client(struct notifier_block *nb)
{
	return 0;
}

static inline int mi_disp_unregister_client(struct notifier_block *nb)
{
	return 0;
}

#endif /* __GF_COMPAT_66_H */
