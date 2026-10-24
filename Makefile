# Junebug Linux build entry points. Needs root (sudo) for rootfs/iso; see docs/BUILDING.md.
SHELL := /bin/bash
.DEFAULT_GOAL := help
# Target platform (see build.conf): pc (x86-64 ISO) | rpi (Raspberry Pi arm64 SD image)
PLATFORM ?= pc
export PLATFORM
QEMU_DEPS_pc  := qemu-system-x86 ovmf
QEMU_DEPS_rpi := qemu-system-arm qemu-efi-aarch64

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

deps: ## Install build dependencies (Debian/Ubuntu host)
	sudo apt-get update -q
	sudo apt-get install -y -q --no-install-recommends mmdebstrap squashfs-tools xorriso mtools dosfstools \
	    jq curl ca-certificates minisign shellcheck qemu-utils fdisk e2fsprogs xz-utils $(QEMU_DEPS_$(PLATFORM))

rootfs: ## Stage 1: bootstrap + customise the Debian rootfs
	scripts/build-rootfs.sh

iso: rootfs ## Stage 2 (pc): squashfs + hybrid BIOS/UEFI ISO
	scripts/build-iso.sh

image: rootfs ## Stage 2 for PLATFORM: ISO (pc) or SD card image (rpi)
	@if [ "$(PLATFORM)" = rpi ]; then scripts/build-rpi-image.sh; else scripts/build-iso.sh; fi

manifest: ## Stage 3: manifest.json (+ minisign signature when a key is given)
	scripts/make-manifest.sh

release: image manifest ## Full build: rootfs -> image -> manifest

test-boot: ## QEMU smoke tests (pc: ISO BIOS/UEFI + install; rpi: image via arm64 UEFI)
	scripts/boot-test.sh $(if $(filter rpi,$(PLATFORM)),rpi,all)

lint: ## shellcheck, bash -n, actionlint, JSON
	scripts/lint.sh

clean: ## Remove build output (needs sudo: rootfs is root-owned)
	sudo rm -rf out

.PHONY: help deps rootfs iso image manifest release test-boot lint clean
