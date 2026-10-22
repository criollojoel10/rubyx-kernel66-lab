# Huella Goodix de ruby portada a 6.6
obj-$(CONFIG_GOODIX_CAP_FINGERPRINT) := gf_spi_tee.o gf_spi_factory.o

# el TEEI 400 (Microtrust) es el TEE de ruby
ccflags-y += -I$(srctree)/drivers/tee/teei/400/tz_driver/include/
ccflags-y += -I$(srctree)/drivers/tee/teei/400/common/include/
