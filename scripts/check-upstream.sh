#!/usr/bin/env bash
# Compares upstream component versions (browser, kernel) with the latest published release.
# Prints "changed=true|false", "reason=..." and "tag=vYYYY.MM.DD[.N]" (GitHub Actions output format).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
require_tools curl jq gh

REPO_SLUG="${GITHUB_REPOSITORY:-kaeferfreund/junebug-linux}"

madison() { # package suite -> version
    curl -fsSL "https://qa.debian.org/madison.php?package=$1&text=on&s=$2&a=$ARCH" | awk -F'|' 'NR==1{gsub(/ /,"",$2); print $2}'
}
case "$BROWSER" in
    chrome)  browser_new="$(curl -fsSL https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages | awk '/^Package: google-chrome-stable$/{f=1} f&&/^Version:/{print $2; exit}')" ;;
    firefox) browser_new="$(curl -fsSL https://packages.mozilla.org/apt/dists/mozilla/main/binary-amd64/Packages | awk '/^Package: firefox$/{f=1} f&&/^Version:/{print $2; exit}')" ;;
    chromium) browser_new="$(madison chromium "$SUITE-security")"; [[ -n "$browser_new" ]] || browser_new="$(madison chromium "$SUITE")" ;;
esac
kernel_new="$(madison "linux-image-$ARCH" "$KERNEL_SUITE")"
[[ -n "$browser_new" && -n "$kernel_new" ]] || die "could not determine upstream versions (browser='$browser_new' kernel='$kernel_new')"

manifest="$(gh release download --repo "$REPO_SLUG" --pattern manifest.json --output - 2>/dev/null || true)"
browser_cur="$(jq -r '.browser_version // ""' <<<"${manifest:-null}" 2>/dev/null || true)"
kernel_cur="$(jq -r '.kernel // ""' <<<"${manifest:-null}" 2>/dev/null || true)"
# manifest.kernel is the uname-style version (7.2.9-amd64); compare the package version's upstream part.
kernel_new_short="$(sed -E 's/-.*//' <<<"$kernel_new")"
kernel_cur_short="$(sed -E 's/-.*//' <<<"$kernel_cur")"

changed=false; reason=""
[[ -z "$manifest" ]] && { changed=true; reason="no release yet"; }
[[ "$browser_new" != "$browser_cur" ]] && { changed=true; reason="$reason browser:${browser_cur:-none}->$browser_new"; }
[[ "$kernel_new_short" != "$kernel_cur_short" ]] && { changed=true; reason="$reason kernel:${kernel_cur_short:-none}->$kernel_new_short"; }

base="v$(date -u +%Y.%m.%d)"; tag="$base"; n=0
while git -C "$REPO_DIR" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; do
    n=$((n+1)); tag="$base.$n"
done
echo "changed=$changed"
echo "reason=${reason# }"
echo "tag=$tag"
echo "browser_version=$browser_new"
echo "kernel_version=$kernel_new"
