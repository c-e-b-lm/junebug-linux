# Building locally

Requirements: Debian 12+/Ubuntu 24.04+ on x86-64, root via sudo, ~10 GB free disk, internet.

```sh
make deps                          # one-time
make iso                           # ~10-15 min: out/release/junebug-<version>-amd64.iso
MINISIGN_KEY_FILE=~/minisign.key make manifest
make test-boot                     # QEMU smoke tests, needs /dev/kvm for reasonable speed
sudo make clean
```

Variables (`build.conf`): `BROWSER=chrome|firefox|chromium`, `KERNEL_SUITE=trixie|trixie-backports|sid`,
`FIRMWARE_NVIDIA=1`, `SQUASHFS_COMP=zstd|xz`, `VERSION=2026.10.20`, `UPDATE_URL=...`, `MIRROR=...`.

Quick iteration without rebuilding the rootfs: edit `overlay/` or `boot/`, then
`sudo scripts/build-rootfs.sh` is only needed when packages or chroot-setup change; otherwise copy
overlay changes into `out/rootfs` and re-run `sudo scripts/build-iso.sh`.

Run the ISO in QEMU by hand:

```sh
qemu-system-x86_64 -enable-kvm -m 2048 -cdrom out/release/*.iso -vga virtio -display gtk \
  -smbios 'type=11,value=io.systemd.credential:kiosk.conf=KIOSK_URL=https://example.org'
```

The build host never needs Debian's keyring package: `build-rootfs.sh` fetches the current
`debian-archive-keyring` over HTTPS and verifies it against the Packages index.
