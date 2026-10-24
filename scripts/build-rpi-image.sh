#!/usr/bin/env bash
# Stage 2 for PLATFORM=rpi: Raspberry Pi SD card image (an installed system, no live installer).
# Input : $OUT_DIR/rootfs, $OUT_DIR/bootassets
# Output: $OUT_DIR/release/{filesystem.squashfs,vmlinuz,initrd.img,<image>.img.xz,SHA256SUMS,release.env}
#         $OUT_DIR/img/<image>.img (uncompressed, for the QEMU boot test)
#
# Layout (MBR, readable by the Pi boot ROM on Pi 3 and Pi 4):
#   p1 KIOSK_EFI  FAT32 (type 0x0c, active): Pi firmware, config.txt, U-Boot, DTBs,
#                 EFI/boot/bootaa64.efi (GRUB), boot/grub/{grub.cfg,grubenv}, kiosk.conf
#   p2 KIOSK_DATA ext4: live/a/{vmlinuz,initrd.img,filesystem.squashfs,version}, live/b/ (empty)
# Partitions are built as files (mkfs.vfat + mtools, mkfs.ext4 -d) and copied into the image:
# no loop devices needed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
need_root "$@"
require_tools mksquashfs mkfs.vfat mcopy mkfs.ext4 sfdisk xz truncate
[[ "$PLATFORM" == rpi ]] || die "build-rpi-image.sh needs PLATFORM=rpi"

ROOTFS="$OUT_DIR/rootfs"
BOOTASSETS="$OUT_DIR/bootassets"
RELEASE="$OUT_DIR/release"
WORK="$OUT_DIR/img"
[[ -d "$ROOTFS/etc/kiosk" ]] || die "rootfs missing; run build-rootfs.sh first"
[[ -s "$BOOTASSETS/rpi/u-boot.bin" && -s "$BOOTASSETS/bootaa64.efi" ]] || die "Pi boot assets missing; rebuild the rootfs with PLATFORM=rpi"
rm -rf "$RELEASE" "$WORK"
mkdir -p "$RELEASE" "$WORK"

stage_system_files "$ROOTFS" "$RELEASE"

CMDLINE="$(tr -d '\n' < "$REPO_DIR/boot/cmdline.txt")"
render() { sed -e "s|@CMDLINE@|$CMDLINE|g" -e "s|@DIST_NAME@|$DIST_NAME|g" -e "s|@VERSION@|$VERSION|g" "$1"; }

# --- boot partition tree ------------------------------------------------------
BOOT="$WORK/boot"
mkdir -p "$BOOT/EFI/boot" "$BOOT/boot/grub" "$BOOT/.disk"
find "$BOOTASSETS/rpi" -maxdepth 1 -type f ! -name VERSIONS -exec cp {} "$BOOT/" \;
cp "$REPO_DIR/boot/rpi-config.txt" "$BOOT/config.txt"
cp "$BOOTASSETS/bootaa64.efi" "$BOOT/EFI/boot/bootaa64.efi"
render "$REPO_DIR/boot/grub-installed.cfg" > "$BOOT/boot/grub/grub.cfg"
# grubenv is a fixed 1024-byte block padded with '#' (what grub-editenv writes).
env_block="# GRUB Environment Block"$'\n'"slot=a"$'\n'"trial=0"$'\n'"tried=0"$'\n'
{ printf '%s' "$env_block"; head -c $((1024 - ${#env_block})) /dev/zero | tr '\0' '#'; } > "$BOOT/boot/grub/grubenv"
echo "$DIST_NAME $VERSION ($ARCH, $PLATFORM)" > "$BOOT/.disk/info"
cp "$REPO_DIR/config/kiosk.conf" "$BOOT/kiosk.conf"
[[ -d "$REPO_DIR/config/network" ]] && cp -r "$REPO_DIR/config/network" "$BOOT/network"

# --- data partition tree --------------------------------------------------------
DATA="$WORK/data"
mkdir -p "$DATA/live/a" "$DATA/live/b"
cp "$RELEASE"/{vmlinuz,initrd.img,filesystem.squashfs} "$DATA/live/a/"
echo "$VERSION" > "$DATA/live/a/version"

# --- sizes (MiB) ----------------------------------------------------------------
OFFSET_MB=4
BOOT_MB="${RPI_BOOT_MB:-256}"
sys_mb=$(( $(du -smc "$RELEASE"/{vmlinuz,initrd.img,filesystem.squashfs} | tail -1 | cut -f1) ))
# Room for slot b (an update) plus ext4 overhead. Growing to the card size: see docs/RASPBERRY-PI.md.
DATA_MB="${RPI_DATA_MB:-$(( sys_mb * 22 / 10 + 256 ))}"
log "partitions: boot ${BOOT_MB} MiB, data ${DATA_MB} MiB (system ${sys_mb} MiB)"

# --- filesystems ----------------------------------------------------------------
truncate -s "${BOOT_MB}M" "$WORK/boot.fat"
mkfs.vfat -F 32 -n KIOSK_EFI "$WORK/boot.fat" >/dev/null
mcopy -s -i "$WORK/boot.fat" "$BOOT"/* "$BOOT/.disk" ::/
# GRUB must read this filesystem: keep to features its ext2 driver knows.
mkfs.ext4 -q -F -L KIOSK_DATA -O ^metadata_csum_seed,^orphan_file -E root_owner=0:0 \
    -d "$DATA" "$WORK/data.ext4" "${DATA_MB}M"

# --- disk image -------------------------------------------------------------------
IMG="$WORK/$IMAGE_NAME.img"
truncate -s "$(( OFFSET_MB + BOOT_MB + DATA_MB ))M" "$IMG"
sfdisk --quiet "$IMG" <<EOF
label: dos
unit: sectors
start=$(( OFFSET_MB * 2048 )), size=$(( BOOT_MB * 2048 )), type=c, bootable
start=$(( (OFFSET_MB + BOOT_MB) * 2048 )), size=$(( DATA_MB * 2048 )), type=83
EOF
dd if="$WORK/boot.fat" of="$IMG" bs=1M seek="$OFFSET_MB" conv=notrunc,sparse status=none
dd if="$WORK/data.ext4" of="$IMG" bs=1M seek="$(( OFFSET_MB + BOOT_MB ))" conv=notrunc,sparse status=none
rm -f "$WORK/boot.fat" "$WORK/data.ext4"; rm -rf "$DATA"

log "xz -> $IMAGE_NAME.img.xz"
xz -T0 -6 -c "$IMG" > "$RELEASE/$IMAGE_NAME.img.xz"

# --- checksums + release metadata ---------------------------------------------
cp "$ROOTFS/etc/kiosk/release" "$RELEASE/release.env"
cp "$BOOTASSETS/rpi/VERSIONS" "$RELEASE/boot-versions.txt"
( cd "$RELEASE" && sha256sum "$IMAGE_NAME.img.xz" filesystem.squashfs vmlinuz initrd.img > SHA256SUMS )
chown -R --reference="$REPO_DIR" "$RELEASE" "$WORK" 2>/dev/null || true
log "done:"
ls -lh "$RELEASE" "$IMG"
