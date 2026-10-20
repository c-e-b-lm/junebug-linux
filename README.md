<p align="center">
  <img src="docs/logo.svg" width="168" alt="Junebug Linux logo">
</p>

<h1 align="center">Junebug Linux</h1>

<p align="center">
  <em>A tiny Linux that does exactly one thing: boot into a web browser.</em>
</p>

<p align="center">
  <a href="https://github.com/kaeferfreund/junebug-linux/actions/workflows/ci.yml"><img src="https://github.com/kaeferfreund/junebug-linux/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/kaeferfreund/junebug-linux/releases/latest"><img src="https://img.shields.io/github/v/release/kaeferfreund/junebug-linux?label=release&color=f3a63b" alt="Latest release"></a>
  <a href="https://github.com/kaeferfreund/junebug-linux/releases/latest"><img src="https://img.shields.io/github/downloads/kaeferfreund/junebug-linux/total?color=2b3a4e" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT"></a>
</p>

Junebug (German: *Maikäfer*) is a minimal, image-based Linux in the spirit of
[Porteus Kiosk](https://porteus-kiosk.org/): it starts straight into Google Chrome,
on Google with an address bar and tabs when no start URL is configured. A configured URL enables kiosk
mode; `KIOSK_MODE=browser` keeps browser controls visible even with a start URL.
It has no desktop or login screen. It is built from stock Debian with
plain shell scripts, so every byte in the image is traceable, and it updates itself from signed
GitHub releases.

## Highlights

| | |
|---|---|
| **Browser-only** | Chrome stable with normal browser controls by default, optional kiosk mode, on the [cage](https://github.com/cage-kiosk/cage) Wayland compositor. No desktop, no window manager, no login screen. Firefox and Debian Chromium are build options. |
| **Runs almost anywhere** | Any x86-64 PC from roughly 2008 on: legacy BIOS and UEFI, Secure Boot (Debian shim), Intel/AMD/NVIDIA graphics with software-rendering fallback, Wi-Fi firmware for Intel, Realtek, Atheros, Broadcom and MediaTek. |
| **Newest Debian kernel** | Linux from `trixie-backports`, signed for Secure Boot. Switch to `sid` for the bleeding edge. |
| **Read-only, stateless** | Squashfs root, tmpfs overlay, volatile journal. A reboot restores a pristine system. |
| **Signed A/B updates** | Installed devices check nightly, verify a minisign-signed manifest, stage the new version in the inactive slot and roll back automatically if it does not come up. |
| **One config file** | `kiosk.conf` on the boot medium: URL, language, keyboard, Wi-Fi, SSH key, allow-list, and more. |
| **Fully automated releases** | GitHub Actions builds, boot-tests in QEMU (BIOS, UEFI, install), signs and publishes. A weekly job cuts a release whenever Chrome or the kernel moved. |

## Quick start

1. Download the latest `junebug-*.iso` from [Releases](https://github.com/kaeferfreund/junebug-linux/releases/latest).
2. Write it to a USB stick:
   ```sh
   dd if=junebug-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
3. Boot from the stick. The browser opens Google with an address bar and tabs. Setting `KIOSK_URL` enables kiosk mode; use `KIOSK_MODE=browser` for a start URL with browser controls.
4. For a permanent installation with automatic updates choose **Install to disk** in the boot menu.
   Afterwards edit `kiosk.conf` on the `KIOSK_EFI` partition (FAT32, readable from any PC):
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
[config/kiosk.conf](config/kiosk.conf). Sources are merged in this order, later wins:

1. built-in defaults (`/etc/kiosk/kiosk.conf`)
2. `kiosk.conf` in the root of the boot medium (ISO root; baked in from `config/kiosk.conf` at build time)
3. `kiosk.conf` on the `KIOSK_EFI` partition (installed systems)
4. `kiosk.conf` on any USB stick labelled `KIOSKCFG`
5. systemd system credential `kiosk.conf` (SMBIOS, VMs)
6. kernel command line: `kiosk.url=...`, `kiosk.mode=browser`, `kiosk.debug=1`

## How it works

```
GRUB / isolinux ──▶ Debian kernel + live-boot initramfs ──▶ squashfs (read-only) + tmpfs overlay
                                                               │
                      systemd ── kiosk-config (merge kiosk.conf, Wi-Fi, policies)
                              ├─ kiosk.service: cage ──▶ google-chrome [--kiosk] [URL]
                              ├─ kiosk-update.timer: signed manifest ──▶ inactive slot ──▶ trial boot
                              └─ kiosk-mark-good: browser alive after 90 s ──▶ slot confirmed
```

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/UPDATES.md](docs/UPDATES.md),
[docs/HARDWARE.md](docs/HARDWARE.md).

## Building

Images are built on GitHub Actions (x86-64). Locally you need a Debian/Ubuntu x86-64 host with root,
or Docker (`docker run --privileged`):

```sh
make deps        # mmdebstrap, squashfs-tools, xorriso, qemu, ovmf, ...
make iso         # out/release/junebug-<version>-amd64.iso
make manifest    # out/release/manifest.json (+ signature with MINISIGN_KEY_FILE=...)
make test-boot   # QEMU: ISO on BIOS, ISO on UEFI, install to disk + boot both ways
```

Build options live in [build.conf](build.conf) and can be overridden from the environment
(`BROWSER=firefox make iso`, `FIRMWARE_NVIDIA=1`, `SQUASHFS_COMP=xz`, `KERNEL_SUITE=sid`).
See [docs/BUILDING.md](docs/BUILDING.md).

## Releasing

The step-by-step recipe (German) is in [KOCHREZEPT.md](KOCHREZEPT.md). Short version:

```sh
git tag -a v2026.10.20 -m "Chrome 155, kernel 7.2" && git push origin v2026.10.20
```

GitHub Actions builds, tests, signs and publishes the release; installed devices pick it up the
following night. The **Auto release** workflow does the same every Monday when a new Chrome or
kernel version is available.

## Repository layout

```
build.conf                 build-time options (browser, kernel suite, mirrors, update URL)
packages/*.list            Debian package lists (base, firmware)
scripts/                   build-rootfs.sh → chroot-setup.sh → build-iso.sh → make-manifest.sh, boot-test.sh
overlay/                   files copied into the image (systemd units, kiosk-* tools, browser policies)
boot/                      GRUB / isolinux templates, kernel command line
config/kiosk.conf          configuration shipped on the ISO
docs/                      ARCHITECTURE, CONFIG, UPDATES, HARDWARE, BUILDING, logo
.github/workflows/         ci.yml, release.yml, auto-release.yml
```

## License

MIT. Debian, Linux, cage and the firmware blobs come with their own licenses. Google Chrome is
proprietary and downloaded from Google at build time under its own terms.
