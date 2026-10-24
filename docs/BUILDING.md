# Building locally

Requirements: Debian 12+/Ubuntu 24.04+ on x86-64, root via sudo, ~10 GB free disk, internet.

```sh
make deps                          # one-time
make iso                           # ~10-15 min: out/release/junebug-<version>-amd64.iso
MINISIGN_KEY_FILE=~/minisign.key make manifest
make test-boot                     # QEMU smoke tests, needs /dev/kvm for reasonable speed
sudo make clean
```

Raspberry Pi image (arm64): build on an arm64 host (or an x86-64 host with `qemu-user-static`
binfmt support, much slower), see [RASPBERRY-PI.md](RASPBERRY-PI.md):

```sh
PLATFORM=rpi make deps
PLATFORM=rpi sudo -E make image    # out/release/junebug-<version>-arm64-rpi.img.xz
PLATFORM=rpi sudo -E make test-boot
```

Variables (`build.conf`): `PLATFORM=pc|rpi`, `BROWSER=chrome|firefox|chromium`, `KERNEL_SUITE=trixie|trixie-backports|sid`,
`FIRMWARE_NVIDIA=1`, `SQUASHFS_COMP=zstd|xz`, `VERSION=2026.10.20`, `UPDATE_URL=...`, `MIRROR=...`.

Quick iteration without rebuilding the rootfs: edit `overlay/` or `boot/`, then
`sudo scripts/build-rootfs.sh` is only needed when packages or chroot-setup change; otherwise copy
overlay changes into `out/rootfs` and re-run `sudo scripts/build-iso.sh`.

## Building with Docker (no root on the host needed)

Any x86-64 host with Docker works, e.g. a VPS or a Debian 12 box without sudo rights:

```sh
git clone https://github.com/kaeferfreund/junebug-linux.git && cd junebug-linux
docker run --rm --privileged -v "$PWD:/src" -w /src -e VERSION=2026.10.20-dev -e DEBIAN_FRONTEND=noninteractive \
  debian:trixie bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    mmdebstrap squashfs-tools xorriso mtools dosfstools jq curl ca-certificates minisign git make \
    && git config --global --add safe.directory /src && make rootfs iso manifest'
ls -lh out/release/
```

`--privileged` is needed because mmdebstrap mounts /proc and /dev inside the chroot. On a 4-core
VPS the whole build takes about 4 minutes; the ISO is roughly 870 MB. QEMU boot tests need
`/dev/kvm` to be usable, so run them on the host or leave them to CI.

Run the ISO in QEMU by hand:

```sh
qemu-system-x86_64 -enable-kvm -m 2048 -cdrom out/release/*.iso -vga virtio -display gtk \
  -smbios 'type=11,value=io.systemd.credential:kiosk.conf=KIOSK_URL=https://example.org'
```

The build host never needs Debian's keyring package: `build-rootfs.sh` fetches the current
`debian-archive-keyring` over HTTPS and verifies it against the Packages index.
