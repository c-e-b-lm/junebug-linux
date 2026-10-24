# Raspberry Pi (arm64) support

Status: **increment 1 (experimental)**. Target boards: Raspberry Pi 4 B, Pi 400, CM4, Pi 3 B/B+
and Zero 2 W (64-bit). The Pi 5 is out of scope for now.

```sh
PLATFORM=rpi sudo -E make image     # -> out/release/junebug-<version>-arm64-rpi.img.xz
```

Write the `.img.xz` with Raspberry Pi Imager ("Use custom") or
`xzcat junebug-*.img.xz | dd of=/dev/sdX bs=4M oflag=sync`, then edit `kiosk.conf` on the
`KIOSK_EFI` partition exactly like on a PC install.

## Design: reuse the PC boot chain instead of inventing a Pi one

The PC build boots `GRUB -> /live/<slot>/vmlinuz` and implements A/B updates with a
`grubenv` (`slot`, `trial`, `tried`). The Pi port keeps all of that unchanged and only puts
two extra stages in front of it, the same approach Fedora and openSUSE use on the Pi:

```
Pi boot ROM / EEPROM
  └─ start*.elf (raspi-firmware)   reads config.txt, loads the upstream device tree
       └─ u-boot.bin (u-boot-rpi, rpi_arm64)   provides UEFI
            └─ EFI/boot/bootaa64.efi (Debian's grub-efi-arm64)
                 └─ boot/grub/grub.cfg = boot/grub-installed.cfg   (same A/B + trial-boot logic)
                      └─ /live/<slot>/{vmlinuz,initrd.img,filesystem.squashfs} on KIOSK_DATA
```

Consequences:

- `kiosk-update`, `kiosk-rollback`, `kiosk-mark-good`, `grub-installed.cfg`, live-boot and the
  whole userland are shared with the PC build. No Pi-specific update code.
- Kernel, firmware and boot loaders come from stock Debian (`linux-image-arm64`,
  `raspi-firmware`, `u-boot-rpi`, `grub-efi-arm64-signed`), keeping the "every byte is
  traceable" property.
- The same `.img` also boots on generic arm64 UEFI machines (and QEMU `virt` + AAVMF, which is
  what CI tests), because the FAT partition carries `EFI/boot/bootaa64.efi`.
- There is no ISO/live installer on the Pi: the SD card image *is* an installed system
  (MBR: `KIOSK_EFI` FAT32 type 0x0c, `KIOSK_DATA` ext4 with slot `a` filled, slot `b` empty).

Why not the Pi-native `tryboot`/`autoboot.txt` mechanism? It needs the reboot-flag support of the
Raspberry Pi kernel, is Pi-4/5-only and would require a second implementation of the A/B logic.
U-Boot + GRUB gives one implementation for every platform.

## Build parameters

| Variable | Values | Notes |
|---|---|---|
| `PLATFORM` | `pc` (default), `rpi` | `rpi` implies `ARCH=arm64` |
| `ARCH` | `amd64`, `arm64` | normally derived from `PLATFORM` |
| `BROWSER` | `chrome` (default), `chromium`, `firefox` | Google ships `google-chrome-stable` for arm64 since mid-2026; `chromium` is the fully Debian-built alternative |

Package lists: `packages/base.list` (all), `packages/base-<arch>.list` (boot loaders),
`packages/firmware-<platform>.list`.

Updates: each platform has its own manifest (`manifest.json` for `pc`,
`manifest-arm64-rpi.json` for `rpi`); release files of non-PC platforms are prefixed
(`arm64-rpi-filesystem.squashfs` ...) so one GitHub release can carry all platforms.
`kiosk-update` refuses manifests whose `arch`/`platform` do not match the running system.

## Increments

1. **Buildable and boot-tested image** (this PR): platform switch, package lists, Pi boot
   partition (firmware, `config.txt`, U-Boot, DTBs, GRUB), `.img.xz` builder without loop
   devices, per-platform manifest + arch guard in the updater, QEMU `virt`/AAVMF boot test,
   CI job on a native `ubuntu-24.04-arm` runner.
2. **Real hardware + releases**: test on Pi 4 / Pi 3 (HDMI, Wi-Fi, audio, USB keyboard),
   fix `config.txt`/DTB issues, grow `KIOSK_DATA` to the card size on first boot, publish the
   rpi image + prefixed files + manifest in `release.yml` and `auto-release.yml`
   (`check-upstream.sh` for arm64).
3. **Polish**: refresh firmware/DTBs/U-Boot on the boot partition after a confirmed update,
   hardware watchdog for hung trial boots, `kiosk-install` from SD to USB SSD, docs
   (HARDWARE.md), optional Pi-5 support (needs a different U-Boot/kernel story).

## Known risks / open questions

- Hardware video decoding: neither Chrome nor Debian's Chromium uses the Pi's V4L2 decoders;
  video playback is CPU-bound (fine for dashboards, weak for 1080p video).
- Pi 3 / Zero 2 W have 1 GB RAM or less: Chrome works but is tight.
- Firmware/DTBs on the boot partition are not yet updated by A/B updates (increment 3);
  kernel and userland are.
