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

## Synology Virtual Machine Manager

Synology VMM compatibility is not covered by the QEMU CI tests. On a DS723+
running DSM 7.4.1-90080 Update 1, the development ISO has been reported to stop
updating the legacy ISOLINUX menu at "Automatic boot in 1 second". Switching
to UEFI and VGA allowed the browser to start, but the console showed stale
text and mouse trails. Switching to VMVGA then produced a black console.
These observations do not establish the underlying cause.

A separate local QEMU test with `-vga vmware` and the development image's kernel
and initrd failed to initialize `vmwgfx` (`Hardware has no pitchlock`, error -38).
Cage then reported `Found 0 GPUs` and `Failed to open any DRM device`. This
explains a possible VMVGA failure path; logs from the Synology guest are still
needed to confirm whether it is the same failure there.

For that combination, keep UEFI, select VGA, and try the existing **safe graphics**
boot entry (`nomodeset`). This is a troubleshooting step, not a verified fix.
If it also fails, use the debug boot entry and collect `journalctl -b -u kiosk.service`
and `dmesg` from a shell or configured SSH connection before changing more settings.
The CI self-test checks that Cage and the browser processes stay running; it does
not verify that the displayed page or the VNC console renders correctly.
