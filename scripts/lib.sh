#!/usr/bin/env bash
# Shared helpers for the build scripts. Source, do not execute.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPTS_DIR")"
OUT_DIR="${OUT_DIR:-$REPO_DIR/out}"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

load_build_conf() {
    # shellcheck source=../build.conf
    source "$REPO_DIR/build.conf"
    VERSION="${VERSION:-$(detect_version)}"
    IMAGE_NAME="${DIST_ID}-${VERSION}-${ARCH}"
    export DIST_NAME DIST_ID SUITE KERNEL_SUITE ARCH BROWSER FIRMWARE_NVIDIA MIRROR \
        SECURITY_MIRROR SQUASHFS_COMP UPDATE_URL UPDATE_CHANNEL ISO_LABEL VERSION IMAGE_NAME
}

# Version: from an explicit VERSION, a release tag (v2026.10.20 -> 2026.10.20), or a dev marker.
detect_version() {
    local tag
    if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
        tag="$GITHUB_REF_NAME"
    elif tag="$(git -C "$REPO_DIR" describe --tags --exact-match 2>/dev/null)"; then
        :
    else
        local sha
        sha="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
        echo "0.0.0+dev.${sha}"
        return
    fi
    echo "${tag#v}"
}

# Read a package list file, dropping comments and blank lines, joined by commas.
package_list() {
    grep -hvE '^\s*(#|$)' "$@" | tr '\n' ',' | sed 's/,$//'
}

need_root() {
    if [[ $EUID -ne 0 ]]; then
        exec sudo -E --preserve-env=PATH "$0" "$@"
    fi
}

require_tools() {
    local missing=()
    for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
    [[ ${#missing[@]} -eq 0 ]] || die "missing tools: ${missing[*]}"
}
