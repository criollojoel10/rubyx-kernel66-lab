# Driver de la huella Goodix de ruby
obj-$(CONFIG_GOODIX_CAP_FINGERPRINT) += goodix_cap.o
goodix_cap-y += gf_spi_tee.o gf_spi_factory.o

# teei_fp.h lo pone el TEEI 400 que port/mtk-drivers/apply.sh copia al arbol;
# compilamos contra esa copia para no duplicar la cabecera.
ccflags-y += -I$(srctree)/drivers/tee/teei/400/common/include
ccflags-y += -I$(srctree)/drivers/tee/teei/400/teei_fp
ccflags-y += -I$(srctree)/drivers/tee/teei/400/tz_driver/include
