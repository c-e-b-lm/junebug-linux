#!/usr/bin/env bash
# Stage 3: write manifest.json for the in-image updater and (optionally) sign it with minisign.
# Signing: set MINISIGN_SECRET_KEY (file content) or MINISIGN_KEY_FILE (path).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
require_tools jq sha256sum
RELEASE="$OUT_DIR/release"
[[ -s "$RELEASE/release.env" ]] || die "release dir incomplete; run build-iso.sh first"
# shellcheck disable=SC1091
source "$RELEASE/release.env"

# name: file name on the device; src: release asset name (prefixed for non-pc platforms)
file_entry() {
    local f="$1"
    jq -n --arg name "$f" --arg src "$RELEASE_PREFIX$f" --arg sha "$(sha256sum "$RELEASE/$f" | cut -d' ' -f1)" \
        --argjson size "$(stat -c %s "$RELEASE/$f")" '{name:$name, src:$src, sha256:$sha, size:$size}'
}
# The image a user downloads: the ISO (pc) or the compressed SD card image (rpi).
IMAGE_FILE="$IMAGE_NAME.iso"; [[ "$PLATFORM" == pc ]] || IMAGE_FILE="$IMAGE_NAME.img.xz"
MANIFEST="$RELEASE/$MANIFEST_NAME"

jq -n \
    --arg version "$VERSION" --arg channel "$CHANNEL" --arg dist "$DIST_ID" \
    --arg kernel "$KERNEL" --arg browser "$BROWSER" --arg browser_version "$BROWSER_VERSION" \
    --arg date "$BUILD_DATE" --arg iso "$IMAGE_FILE" --arg arch "$ARCH" --arg platform "$PLATFORM" \
    --argjson files "$(jq -s . <(file_entry filesystem.squashfs) <(file_entry vmlinuz) <(file_entry initrd.img))" \
    '{schema:1, dist:$dist, arch:$arch, platform:$platform, version:$version, channel:$channel,
      build_date:$date, kernel:$kernel, browser:$browser, browser_version:$browser_version,
      iso:$iso, files:$files}' \
    > "$MANIFEST"
log "$MANIFEST_NAME written"

KEYFILE="${MINISIGN_KEY_FILE:-}"
if [[ -z "$KEYFILE" && -n "${MINISIGN_SECRET_KEY:-}" ]]; then
    KEYFILE="$(mktemp)"; trap 'rm -f "$KEYFILE"' EXIT
    printf '%s\n' "$MINISIGN_SECRET_KEY" > "$KEYFILE"
fi
if [[ -n "$KEYFILE" ]]; then
    require_tools minisign
    minisign -S -W -s "$KEYFILE" -m "$MANIFEST" \
        -t "$DIST_ID $VERSION $ARCH-$PLATFORM" -x "$MANIFEST.minisig"
    minisign -V -q -p "$REPO_DIR/overlay/etc/kiosk/update.pub" -m "$MANIFEST" \
        || die "manifest signature does not verify against overlay/etc/kiosk/update.pub"
    log "manifest.json signed and verified"
else
    warn "no signing key: $MANIFEST_NAME left unsigned (installed systems will refuse it)"
fi
jq . "$MANIFEST"
