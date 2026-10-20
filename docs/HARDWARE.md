# Hardware support

Target: "as many x86-64 devices as possible". The image ships Debian's full kernel module set
and the non-free firmware packages, so hardware support equals Debian trixie with a backports kernel.

| Area | Status |
|---|---|
| CPU | any x86-64 (Intel/AMD, 2008+). 32-bit x86 is not supported |
| Firmware | legacy BIOS (isolinux / grub i386-pc) and UEFI incl. Secure Boot (Debian shim) |
| Graphics | Intel, AMD, NVIDIA (nouveau; GSP firmware for Turing+ optional via `FIRMWARE_NVIDIA=1`), VirtIO/QXL/Bochs; `simpledrm` fallback for anything with a UEFI/VESA framebuffer (`nomodeset`) |
| Wi-Fi | Intel (iwlwifi), Realtek, Atheros, Broadcom (brcmfmac), MediaTek. Broadcom `wl` (proprietary) is not included |
| Ethernet | everything in the Debian kernel |
| Audio | PipeWire with ALSA UCM + SOF firmware (modern Intel laptops) |
| Input | libinput via wlroots: keyboard, mouse, touchpad, touchscreen |
| Storage | USB, SATA, NVMe, eMMC, SD |
| RAM | 2 GB minimum, 4 GB recommended; the squashfs stays on the medium unless `toram` is chosen |
| Tested in CI | QEMU: SeaBIOS + OVMF, VirtIO disk/network, Bochs VGA (software rendering) |

Tips:
- Boot menu "safe graphics" (`nomodeset`) if the screen stays black after the boot menu.
- Old Atom/Celeron netbooks work but Chrome on software rendering is slow; prefer machines with a
  working Mesa driver (Intel HD Graphics 2010+, AMD GCN+).
- For a device that needs a special kernel parameter, add it to `boot/cmdline.txt` and rebuild,
  or press `e` in the boot menu for a one-off.
- Size vs. hardware coverage: `packages/firmware.list` is where to trim.
