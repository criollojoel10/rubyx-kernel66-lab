SHELL := /bin/bash

.PHONY: help fetch build collect verify inventory classify audit clean

help:
	@echo "make fetch    clona UN1CA/kernel_samsung_a34x @ 6.6.127 y su submódulo"
	@echo "make build    ejecuta build_kernel.sh oficial (Kleaf/Bazel)"
	@echo "make collect  recoge Image, config, symvers y hashes"
	@echo "make verify   valida versión, artefactos y ausencia de errores silenciados"
	@echo "make inventory  compara compatibles DTS ruby 4.19 vs A34 6.6"
	@echo "make classify  clasifica los ruby-only por driver"
	@echo "make audit     audita includes/API de los drivers a portar"
	@echo "make clean    borra sources/, artifacts/ y logs/"

fetch:
	./scripts/fetch-a34-reference.sh

build:
	./scripts/build-a34-reference.sh

collect:
	./scripts/collect-a34-artifacts.sh

verify:
	./scripts/verify-a34-build.py

inventory:
	./scripts/inventory-compatibles.py

classify:
	./scripts/classify-ruby-only.py

audit:
	./scripts/audit-port-drivers.py

clean:
	rm -rf sources artifacts logs out
