#!/usr/bin/env bash
# Stage 2: squashfs + hybrid BIOS/UEFI ISO + release files.
# Input : $OUT_DIR/rootfs, $OUT_DIR/bootassets
# Output: $OUT_DIR/release/{filesystem.squashfs,vmlinuz,initrd.img,<image>.iso,SHA256SUMS}
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
need_root "$@"
require_tools mksquashfs xorriso mformat mcopy mmd mkfs.vfat
[[ "$PLATFORM" == pc ]] || die "build-iso.sh builds the pc ISO; PLATFORM=$PLATFORM uses build-rpi-image.sh (make image)"

ROOTFS="$OUT_DIR/rootfs"
BOOTASSETS="$OUT_DIR/bootassets"
RELEASE="$OUT_DIR/release"
ISO_DIR="$OUT_DIR/iso"
[[ -d "$ROOTFS/etc/kiosk" ]] || die "rootfs missing; run build-rootfs.sh first"
rm -rf "$RELEASE" "$ISO_DIR"
mkdir -p "$RELEASE" "$ISO_DIR"/{live,boot/grub,isolinux,EFI/boot,.disk}

stage_system_files "$ROOTFS" "$RELEASE"

# --- ISO tree -----------------------------------------------------------------
CMDLINE="$(tr -d '\n' < "$REPO_DIR/boot/cmdline.txt")"
render() { sed -e "s|@CMDLINE@|$CMDLINE|g" -e "s|@DIST_NAME@|$DIST_NAME|g" -e "s|@VERSION@|$VERSION|g" "$1"; }

ln "$RELEASE/filesystem.squashfs" "$ISO_DIR/live/filesystem.squashfs"
ln "$RELEASE/vmlinuz" "$ISO_DIR/live/vmlinuz"
ln "$RELEASE/initrd.img" "$ISO_DIR/live/initrd.img"
render "$REPO_DIR/boot/grub-iso.cfg" > "$ISO_DIR/boot/grub/grub.cfg"
render "$REPO_DIR/boot/isolinux.cfg" > "$ISO_DIR/isolinux/isolinux.cfg"
cp "$BOOTASSETS"/{isolinux.bin,ldlinux.c32,menu.c32,libutil.c32} "$ISO_DIR/isolinux/"
cp "$BOOTASSETS/bootx64.efi" "$BOOTASSETS/grubx64.efi" "$ISO_DIR/EFI/boot/"
echo "$DIST_NAME $VERSION ($ARCH)" > "$ISO_DIR/.disk/info"
cp "$REPO_DIR/config/kiosk.conf" "$ISO_DIR/kiosk.conf"
[[ -d "$REPO_DIR/config/network" ]] && cp -r "$REPO_DIR/config/network" "$ISO_DIR/network"

# EFI System Partition image for El Torito (shim + signed grub; grub.cfg comes from the ISO).
EFI_IMG="$ISO_DIR/boot/grub/efi.img"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=8 status=none
mkfs.vfat -F 12 -n EFIBOOT "$EFI_IMG" >/dev/null
mmd -i "$EFI_IMG" ::EFI ::EFI/boot
mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/boot/bootx64.efi" "$ISO_DIR/EFI/boot/grubx64.efi" ::EFI/boot/

# --- ISO ----------------------------------------------------------------------
ISO="$RELEASE/$IMAGE_NAME.iso"
log "xorriso -> $ISO"
xorriso -as mkisofs \
    -r -J -joliet-long -l \
    -V "$ISO_LABEL" \
    -o "$ISO" \
    -isohybrid-mbr "$BOOTASSETS/isohdpfx.bin" \
    -partition_offset 16 \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
    "$ISO_DIR" 2>&1 | grep -vE '^(xorriso : UPDATE|Writing to|ISO image produced)' || true
[[ -s "$ISO" ]] || die "ISO was not produced"

# --- checksums + release metadata ---------------------------------------------
cp "$ROOTFS/etc/kiosk/release" "$RELEASE/release.env"
( cd "$RELEASE" && sha256sum "$IMAGE_NAME.iso" filesystem.squashfs vmlinuz initrd.img > SHA256SUMS )
chown -R --reference="$REPO_DIR" "$RELEASE" 2>/dev/null || true
log "done:"
ls -lh "$RELEASE"
