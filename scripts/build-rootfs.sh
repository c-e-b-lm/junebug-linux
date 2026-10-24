#!/usr/bin/env bash
# Stage 1: bootstrap the Debian root filesystem with mmdebstrap and customise it.
# Produces: $OUT_DIR/rootfs (directory) and $OUT_DIR/bootassets (boot loader binaries:
# isolinux/shim/grub for pc; Pi firmware, U-Boot, GRUB and device trees for rpi).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
need_root "$@"
require_tools mmdebstrap curl dpkg-deb jq

ROOTFS="$OUT_DIR/rootfs"
BOOTASSETS="$OUT_DIR/bootassets"
KEYRING_DIR="$OUT_DIR/keyring"
mkdir -p "$OUT_DIR" "$KEYRING_DIR"
rm -rf "$ROOTFS" "$BOOTASSETS"

# --- Debian archive keyring ------------------------------------------------
# The build host (Ubuntu runner) may ship an outdated debian-archive-keyring that lacks the
# trixie release key, so always fetch the current one from Debian over HTTPS and verify the
# .deb against the checksum in the Packages index.
KEYRING="$KEYRING_DIR/debian-archive-keyring.gpg"
if [[ ! -s "$KEYRING" ]]; then
    log "fetching debian-archive-keyring from Debian"
    pkgs="$(curl -fsSL "https://deb.debian.org/debian/dists/$SUITE/main/binary-all/Packages.gz" | gunzip)" || \
        pkgs="$(curl -fsSL "https://deb.debian.org/debian/dists/$SUITE/main/binary-$ARCH/Packages.gz" | gunzip)"
    entry="$(awk 'BEGIN{RS="";FS="\n"} $1=="Package: debian-archive-keyring"' <<<"$pkgs")"
    fname="$(sed -n 's/^Filename: //p' <<<"$entry")"
    fsum="$(sed -n 's/^SHA256: //p' <<<"$entry")"
    [[ -n "$fname" && -n "$fsum" ]] || die "debian-archive-keyring not found in Packages index"
    curl -fsSL -o "$KEYRING_DIR/keyring.deb" "https://deb.debian.org/debian/$fname"
    echo "$fsum  $KEYRING_DIR/keyring.deb" | sha256sum -c --quiet
    dpkg-deb -x "$KEYRING_DIR/keyring.deb" "$KEYRING_DIR/x"
    cp "$KEYRING_DIR/x/usr/share/keyrings/debian-archive-keyring.gpg" "$KEYRING"
fi

# --- Environment passed into the chroot ------------------------------------
BUILD_ENV="$OUT_DIR/build.env"
{
    for v in DIST_NAME DIST_ID SUITE KERNEL_SUITE PLATFORM ARCH MANIFEST_NAME BROWSER FIRMWARE_NVIDIA UPDATE_URL UPDATE_CHANNEL VERSION; do
        printf '%s=%q\n' "$v" "${!v}"
    done
    # shellcheck disable=SC2046  # list of file names
    printf 'FIRMWARE_PACKAGES=%q\n' "$(package_list $(firmware_package_lists))"
    printf 'BUILD_DATE=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$BUILD_ENV"

COMPONENTS="main contrib non-free non-free-firmware"
# shellcheck disable=SC2046  # list of file names
INCLUDE="$(package_list $(base_package_lists))"

log "bootstrapping Debian $SUITE ($ARCH) into $ROOTFS"
mmdebstrap \
    --mode=root \
    --variant=apt \
    --architectures="$ARCH" \
    --keyring="$KEYRING" \
    --include="$INCLUDE" \
    --aptopt='Apt::Install-Recommends "false"' \
    --aptopt='Acquire::Languages "none"' \
    --dpkgopt='path-exclude=/usr/share/doc/*' \
    --dpkgopt='path-include=/usr/share/doc/*/copyright' \
    --dpkgopt='path-exclude=/usr/share/man/*' \
    --dpkgopt='path-exclude=/usr/share/info/*' \
    --dpkgopt='path-exclude=/usr/share/lintian/*' \
    --dpkgopt='path-exclude=/usr/share/locale/*' \
    --dpkgopt='path-include=/usr/share/locale/locale.alias' \
    --dpkgopt='path-include=/usr/share/locale/de/*' \
    --dpkgopt='path-include=/usr/share/locale/de_DE/*' \
    --customize-hook="copy-in $REPO_DIR/overlay /tmp" \
    --customize-hook="copy-in $REPO_DIR/scripts/chroot-setup.sh /tmp" \
    --customize-hook="copy-in $BUILD_ENV /tmp" \
    --customize-hook="copy-in $REPO_DIR/boot/grub-installed.cfg /tmp" \
    --customize-hook="copy-in $REPO_DIR/boot/cmdline.txt /tmp" \
    --customize-hook='chroot "$1" /bin/bash /tmp/chroot-setup.sh' \
    --customize-hook="sync-out /tmp/bootassets $BOOTASSETS" \
    --customize-hook='rm -rf "$1"/tmp/* "$1"/var/lib/apt/lists/* "$1"/var/cache/apt/*.bin' \
    "$SUITE" "$ROOTFS" \
    "deb $MIRROR $SUITE $COMPONENTS" \
    "deb $MIRROR $SUITE-updates $COMPONENTS" \
    "deb $SECURITY_MIRROR $SUITE-security $COMPONENTS" \
    "deb $MIRROR $SUITE-backports $COMPONENTS"

log "rootfs ready: $(du -sh "$ROOTFS" | cut -f1)"
cat "$ROOTFS/etc/kiosk/release"
