#!/bin/bash
# Stage 1b: runs INSIDE the chroot (invoked by build-rootfs.sh via mmdebstrap).
# Installs kernel, firmware and browser, applies the overlay and configures systemd.
set -euo pipefail
source /tmp/build.env
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

apt_install() { apt-get install -y -q --no-install-recommends "$@"; }

echo ">> apt update"
apt-get update -q

echo ">> kernel + firmware from $KERNEL_SUITE"
FW_PKGS="${FIRMWARE_PACKAGES//,/ }"
[[ "$FIRMWARE_NVIDIA" == "1" ]] && FW_PKGS="$FW_PKGS firmware-nvidia-graphics"
# shellcheck disable=SC2086
apt_install -t "$KERNEL_SUITE" "linux-image-$ARCH" $FW_PKGS

echo ">> browser: $BROWSER"
case "$BROWSER" in
    chrome)
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
            | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
            > /etc/apt/sources.list.d/google-chrome.list
        apt-get update -q
        apt_install google-chrome-stable
        # Chrome's postinst adds its own repo + cron job; keep the pinned source, drop cron.
        rm -f /etc/cron.daily/google-chrome
        BROWSER_PKG=google-chrome-stable
        ;;
    firefox)
        install -d -m 0755 /etc/apt/keyrings
        curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc
        echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
            > /etc/apt/sources.list.d/mozilla.list
        printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla
        apt-get update -q
        apt_install firefox
        BROWSER_PKG=firefox
        ;;
    chromium)
        apt_install chromium
        BROWSER_PKG=chromium
        ;;
    *) echo "unknown BROWSER=$BROWSER" >&2; exit 1 ;;
esac
BROWSER_VERSION="$(dpkg-query -W -f='${Version}' "$BROWSER_PKG")"
KERNEL_VERSION="$(find /lib/modules -mindepth 1 -maxdepth 1 -printf "%f\n" | sort -V | tail -1)"

echo ">> overlay"
cp -a /tmp/overlay/. /
chmod 0755 /usr/local/bin/kiosk-* /usr/share/kiosk/*.sh 2>/dev/null || true
install -m 0644 /tmp/grub-installed.cfg /usr/share/kiosk/grub-installed.cfg
install -m 0644 /tmp/cmdline.txt /usr/share/kiosk/cmdline.txt

echo ">> kiosk user"
if ! id kiosk >/dev/null 2>&1; then
    useradd --create-home --shell /usr/sbin/nologin --comment "Kiosk session" \
        --groups video,audio,input,render kiosk
fi
passwd -l root >/dev/null
echo kiosk > /etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\tkiosk\n::1\tlocalhost ip6-localhost ip6-loopback\n' > /etc/hosts

echo ">> systemd"
systemctl enable kiosk-config.service kiosk.service kiosk-mark-good.service \
    kiosk-update.timer kiosk-update-onboot.timer kiosk-installer.service kiosk-selftest.service \
    NetworkManager.service systemd-timesyncd.service systemd-resolved.service
systemctl disable ssh.service 2>/dev/null || true
systemctl mask getty@tty1.service e2scrub_reap.service apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl set-default graphical.target
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo ">> initramfs (live-boot, zstd)"
update-initramfs -u -k all

echo ">> release info"
install -d /etc/kiosk
cat > /etc/kiosk/release <<REL
VERSION=$VERSION
CHANNEL=$UPDATE_CHANNEL
DIST_NAME="$DIST_NAME"
DIST_ID=$DIST_ID
SUITE=$SUITE
KERNEL_SUITE=$KERNEL_SUITE
KERNEL=$KERNEL_VERSION
BROWSER=$BROWSER
BROWSER_VERSION=$BROWSER_VERSION
BUILD_DATE=$BUILD_DATE
UPDATE_URL=$UPDATE_URL
REL
echo "$VERSION" > /etc/kiosk/version
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"$DIST_NAME $VERSION\"|" /etc/os-release
echo "VARIANT_ID=$DIST_ID" >> /etc/os-release

echo ">> boot assets for the ISO builder"
install -d /tmp/bootassets
cp /usr/lib/ISOLINUX/isolinux.bin /usr/lib/ISOLINUX/isohdpfx.bin /tmp/bootassets/
cp /usr/lib/syslinux/modules/bios/{ldlinux,menu,libutil}.c32 /tmp/bootassets/
cp /usr/lib/shim/shimx64.efi.signed /tmp/bootassets/bootx64.efi
cp /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed /tmp/bootassets/grubx64.efi
apt-get purge -y -q isolinux syslinux-common >/dev/null

echo ">> cleanup"
apt-get autoremove -y -q --purge >/dev/null
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/log/*.log /var/log/apt /tmp/overlay
rm -f /etc/ssh/ssh_host_*   # generated per device at first use (kiosk-config)
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
find /var/log -type f -delete
echo ">> done: kernel $KERNEL_VERSION, $BROWSER_PKG $BROWSER_VERSION"
