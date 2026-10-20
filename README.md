# Junebug Linux

> *Junebug* (Maikäfer): a tiny Linux that does exactly one thing, boot into a web browser.

A minimal, image-based Linux that boots straight into a full-screen web browser. Think
[Porteus Kiosk](https://porteus-kiosk.org/), but built from stock Debian with reproducible scripts,
the newest Debian kernel, Google Chrome stable, and signed A/B over-the-air updates.

- **Base**: Debian 13 "trixie", kernel from `trixie-backports` (7.2.x), signed for **Secure Boot**
- **Browser**: Google Chrome stable (Google's apt repo); `firefox` or Debian `chromium` as build options
- **Display**: [cage](https://github.com/cage-kiosk/cage) Wayland kiosk compositor, Chrome via Ozone/Wayland, software rendering fallback
- **Hardware**: all Debian kernel modules + non-free firmware (Intel, AMD, Realtek, Atheros, Broadcom, MediaTek, microcode); BIOS and UEFI; x86-64 from ~2008 onwards
- **Image**: live-boot squashfs, read-only, everything else in RAM. No package manager at runtime.
- **Updates**: nightly check of GitHub Releases, minisign-verified manifest, download into the inactive slot, trial boot with automatic rollback
- **Config**: one `kiosk.conf` file on the boot medium (URL, language, keymap, Wi-Fi, SSH key, ...)
- **Release pipeline**: GitHub Actions builds, boot-tests in QEMU (BIOS, UEFI, install), signs and publishes; a weekly job cuts a new release whenever Chrome or the kernel moved

## Quick start

1. Download the latest `junebug-*.iso` from [Releases](../../releases/latest).
2. Write it to a USB stick: `dd if=junebug-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`
3. Boot. The default welcome page explains how to set the URL.
4. For a permanent installation with automatic updates choose **Install to disk** in the boot menu
   (or run `kiosk-install /dev/sdX` from a shell). Then edit `kiosk.conf` on the `KIOSK_EFI`
   partition (FAT32, readable from any PC):

   ```ini
   KIOSK_URL=https://example.org/dashboard
   KIOSK_LANG=de
   KIOSK_KEYMAP=de
   KIOSK_WIFI_SSID=MyNetwork
   KIOSK_WIFI_PSK=secret
   ```

Minimum hardware: x86-64 CPU, 2 GB RAM (4 GB recommended for heavy web apps), 2 GB disk or USB stick.

## Configuration

All keys are documented in [docs/CONFIG.md](docs/CONFIG.md) and in the commented template
[config/kiosk.conf](config/kiosk.conf). Sources, later wins:

1. built-in defaults (`/etc/kiosk/kiosk.conf`)
2. `kiosk.conf` in the root of the boot medium (ISO root; baked in from `config/kiosk.conf` at build time)
3. `kiosk.conf` on the `KIOSK_EFI` partition (installed systems)
4. `kiosk.conf` on any USB stick labelled `KIOSKCFG`
5. systemd system credential `kiosk.conf` (SMBIOS/VM use)
6. kernel command line: `kiosk.url=...`, `kiosk.debug=1`

## Building

Builds run on GitHub Actions (x86-64 runner). Locally you need a Debian/Ubuntu x86-64 host with root:

```sh
make deps        # mmdebstrap, squashfs-tools, xorriso, qemu, ovmf, ...
make iso         # out/release/junebug-<version>-amd64.iso
make manifest    # out/release/manifest.json (+ signature with MINISIGN_KEY_FILE=...)
make test-boot   # QEMU: ISO on BIOS, ISO on UEFI, install to disk + boot both ways
```

Build options live in [build.conf](build.conf) and can be overridden from the environment
(`BROWSER=firefox make iso`, `FIRMWARE_NVIDIA=1`, `SQUASHFS_COMP=xz`, `KERNEL_SUITE=sid`).
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together and
[docs/UPDATES.md](docs/UPDATES.md) for the A/B update mechanism.

## Releasing

The step-by-step recipe (German) is in [KOCHREZEPT.md](KOCHREZEPT.md). Short version:

```sh
git tag v2026.10.20 && git push origin v2026.10.20
```

GitHub Actions builds, tests, signs and publishes the release; installed devices pick it up the
following night. The `Auto release` workflow does the same automatically every Monday when a new
Chrome or kernel version is available.

## Layout

```
build.conf                 build-time options
packages/*.list            Debian package lists (base, firmware)
scripts/                   build-rootfs.sh -> chroot-setup.sh -> build-iso.sh -> make-manifest.sh, boot-test.sh
overlay/                   files copied into the image (systemd units, kiosk-* tools, policies)
boot/                      GRUB / isolinux templates, kernel command line
config/kiosk.conf          configuration shipped on the ISO
docs/                      ARCHITECTURE, CONFIG, UPDATES, HARDWARE
.github/workflows/         ci.yml, release.yml, auto-release.yml
```

## License

MIT. Debian, Linux, cage and the firmware blobs come with their own licenses; Google Chrome is
proprietary and downloaded from Google at build time under its own terms.
