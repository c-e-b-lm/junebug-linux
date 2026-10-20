# Junebug Linux build entry points. Needs root (sudo) for rootfs/iso; see docs/BUILDING.md.
SHELL := /bin/bash
.DEFAULT_GOAL := help

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

deps: ## Install build dependencies (Debian/Ubuntu host)
	sudo apt-get update -q
	sudo apt-get install -y -q --no-install-recommends mmdebstrap squashfs-tools xorriso mtools dosfstools \
	    jq curl ca-certificates minisign shellcheck qemu-system-x86 qemu-utils ovmf

rootfs: ## Stage 1: bootstrap + customise the Debian rootfs
	scripts/build-rootfs.sh

iso: rootfs ## Stage 2: squashfs + hybrid BIOS/UEFI ISO
	scripts/build-iso.sh

manifest: ## Stage 3: manifest.json (+ minisign signature when a key is given)
	scripts/make-manifest.sh

release: iso manifest ## Full build: rootfs -> iso -> manifest

test-boot: ## QEMU smoke tests (ISO BIOS/UEFI, install + boot from disk)
	scripts/boot-test.sh all

lint: ## shellcheck, bash -n, actionlint, JSON
	scripts/lint.sh

clean: ## Remove build output (needs sudo: rootfs is root-owned)
	sudo rm -rf out

.PHONY: help deps rootfs iso manifest release test-boot lint clean
