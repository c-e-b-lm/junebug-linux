# Architecture

## Build pipeline

```
packages/*.list, overlay/, boot/            (git)
        │
        ▼
scripts/build-rootfs.sh   mmdebstrap --variant=apt → Debian trixie rootfs (no recommends, no docs/man/locales)
        │                 └─ scripts/chroot-setup.sh (inside chroot):
        │                      kernel+firmware from KERNEL_SUITE, browser from vendor repo,
        │                      overlay, kiosk user, systemd enablement, initramfs (live-boot, zstd),
        │                      /etc/kiosk/release, boot assets (isolinux, shim, signed grub) → out/bootassets
        ▼
scripts/build-iso.sh      mksquashfs (zstd 19) → filesystem.squashfs ; vmlinuz + initrd.img
        │                 ISO tree: live/, boot/grub/grub.cfg, isolinux/, EFI/boot/{bootx64,grubx64}.efi, .disk/info, kiosk.conf
        │                 xorriso: El Torito BIOS (isolinux) + EFI (efi.img) + isohybrid MBR/GPT → dd-able ISO
        ▼
scripts/make-manifest.sh  manifest.json {version, files[name,sha256,size], kernel, browser} + minisign signature
        ▼
scripts/boot-test.sh      QEMU: ISO (SeaBIOS), ISO (OVMF), unattended install to disk, boot disk (OVMF + SeaBIOS)
```

## Boot chain

| Firmware | Path |
|---|---|
| Legacy BIOS, ISO/USB | isohybrid MBR → isolinux → `live/vmlinuz` + `initrd.img` |
| UEFI (+ Secure Boot), ISO/USB | `EFI/boot/bootx64.efi` (Debian shim) → `grubx64.efi` (Debian-signed `gcdx64.efi`: searches `/.disk/info`, loads `/boot/grub/grub.cfg`) → Debian-signed kernel |
| Legacy BIOS, installed | grub i386-pc in the BIOS boot partition → `KIOSK_EFI:/boot/grub/grub.cfg` |
| UEFI, installed | same shim + signed grub from the ESP (removable-media path, plus an NVRAM entry if possible) |

The initramfs is Debian's `live-boot`: it finds the partition that contains `live-media-path`
(`/live` on the ISO, `/live/a` or `/live/b` when installed), mounts the squashfs read-only and
overlays a tmpfs. Nothing is written to the medium during normal operation; the journal is
volatile. A reboot restores the pristine state.

## Runtime

```
systemd (graphical.target)
 ├─ kiosk-config.service   merges kiosk.conf sources → /run/kiosk/{config,env}; hostname, tz, Wi-Fi, SSH, browser policies
 ├─ NetworkManager, systemd-resolved, systemd-timesyncd, pipewire (user)
 ├─ kiosk.service          User=kiosk on tty1, PAM session via logind → cage -d -- <browser> [--kiosk] [URL] ; Restart=always
 ├─ kiosk-mark-good        (installed only) 90 s after start: browser alive → clear trial flag in grubenv
 ├─ kiosk-update-onboot.timer (15 min after boot, no reboot) / kiosk-update.timer (03:00, may reboot)
 ├─ kiosk-installer.service  only with kiosk.installer= on the command line (replaces the session)
 └─ kiosk-selftest.service   only with system credential kiosk.selftest (CI)
```

The compositor is `cage`: one Wayland client, fullscreen, no decorations, no VT switching unless
`KIOSK_DEBUG=1`. If the browser exits or crashes, cage exits, systemd restarts the session.
wlroots falls back to software rendering (`WLR_RENDERER_ALLOW_SOFTWARE=1`) on machines without a
usable GPU driver; the kernel's `simpledrm` provides a framebuffer on any UEFI/VESA system even
without a native driver (`nomodeset` menu entry).

## Disk layout of installed systems

```
GPT
 1  1 MiB   BIOS boot (ef02)           grub core.img for legacy BIOS
 2  512 MiB KIOSK_EFI (FAT32)          EFI/boot/*, boot/grub/{grub.cfg,grubenv,i386-pc/}, .disk/info, kiosk.conf, network/
 3  rest    KIOSK_DATA (ext4)          live/a/{vmlinuz,initrd.img,filesystem.squashfs,version}, live/b/...
```

## Why not ...

- **systemd-sysupdate / UKI / dm-verity**: cleaner, but UEFI-only. Legacy BIOS devices (thin
  clients, old NUCs, cash desks) are a stated target, so GRUB + live-boot + A/B directories it is.
  The updater is ~100 lines and does the same job: signed manifest, hash-verified files, trial boot.
- **mkosi / live-build**: both are fine; the custom scripts are shorter than the configuration
  those tools would need for this layout, and every step is visible in the repository.
- **Debian's own Chromium**: available as `BROWSER=chromium`; Chrome is the default because the
  user asked for it and Google ships updates faster.
- **X11**: cage/Wayland needs no window manager, no xinit, no display manager, and works with
  kernel mode setting on everything made in the last 15 years.
