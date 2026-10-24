#!/usr/bin/env bash
# Boot smoke tests in QEMU. Each test boots, waits for the in-image self test to print
# KIOSK-SELFTEST-OK on the serial port, then powers off.
#   boot-test.sh iso-bios      boot the ISO via isolinux (SeaBIOS)
#   boot-test.sh iso-uefi      boot the ISO via shim+grub (OVMF)
#   boot-test.sh install       install to a virtual disk from the ISO, then boot the disk (UEFI + BIOS)
#   boot-test.sh all           the three pc tests above
#   boot-test.sh rpi           PLATFORM=rpi: boot the SD card image on QEMU "virt" via arm64 UEFI
#                              (AAVMF -> GRUB -> slot a). Covers kernel, initramfs, live-boot, GRUB
#                              A/B config and the browser session; the Pi firmware + U-Boot stage
#                              before GRUB needs real hardware.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
RELEASE="$OUT_DIR/release"
TEST_DIR="$OUT_DIR/test"
ISO="$RELEASE/$IMAGE_NAME.iso"
RPI_IMG="$OUT_DIR/img/$IMAGE_NAME.img"
if [[ "${1:-all}" == rpi ]]; then
    require_tools qemu-system-aarch64 qemu-img timeout
    [[ -s "$RPI_IMG" ]] || die "Pi image missing: $RPI_IMG"
else
    require_tools qemu-system-x86_64 qemu-img timeout
    [[ -s "$ISO" ]] || die "ISO missing: $ISO"
fi
mkdir -p "$TEST_DIR"
TIMEOUT="${BOOT_TIMEOUT:-600}"
MEM="${QEMU_MEM:-2048}"

OVMF_CODE="$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd 2>/dev/null | head -1 || true)"
OVMF_VARS="$(ls /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd 2>/dev/null | head -1 || true)"

accel=(-accel tcg)
[[ -w /dev/kvm ]] && accel=(-accel kvm -cpu host)
QEMU=qemu-system-x86_64
MACHINE=(-vga std)

# Credentials are passed via SMBIOS (systemd picks them up as system credentials).
SELFTEST_CRED=(-smbios "type=11,value=io.systemd.credential:kiosk.selftest=1")

# On GitHub Actions, put a log tail into an error annotation (readable via the checks API
# without downloading artifacts).
ci_annotate() { # title, file
    [[ -n "${GITHUB_ACTIONS:-}" && -s "$2" ]] || return 0
    local msg
    msg="$(tail -n 80 "$2" | tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')"
    msg="${msg//'%'/'%25'}"; msg="${msg//$'\n'/'%0A'}"
    echo "::error title=$1::$msg"
}

run_qemu() { # name, expected-marker, qemu args...
    local name="$1" marker="$2"; shift 2
    local serial="$TEST_DIR/$name.serial.log"
    : > "$serial"
    log "qemu [$name] (timeout ${TIMEOUT}s)"
    set +e
    timeout --foreground "$TIMEOUT" "$QEMU" \
        "${accel[@]}" -m "$MEM" -smp 2 -display none "${MACHINE[@]}" \
        -serial "file:$serial" -monitor none -no-reboot \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        "$@" >"$TEST_DIR/$name.qemu.log" 2>&1
    local rc=$?
    set -e
    if grep -q "$marker" "$serial"; then
        log "[$name] PASS: $(grep -m1 "$marker" "$serial")"
        return 0
    fi
    warn "[$name] FAIL (qemu rc=$rc). Serial log tail:"
    tail -n 60 "$serial" >&2
    ci_annotate "boot test $name: qemu output" "$TEST_DIR/$name.qemu.log"
    ci_annotate "boot test $name: serial tail" "$serial"
    return 1
}

uefi_args() {
    [[ -n "$OVMF_CODE" ]] || die "OVMF firmware not found (install ovmf)"
    cp "$OVMF_VARS" "$TEST_DIR/$1.vars.fd"
    echo "-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE -drive if=pflash,format=raw,file=$TEST_DIR/$1.vars.fd"
}

test_iso_bios() {
    run_qemu iso-bios "KIOSK-SELFTEST-OK" "${SELFTEST_CRED[@]}" -cdrom "$ISO" -boot d
}

test_iso_uefi() {
    # shellcheck disable=SC2046
    run_qemu iso-uefi "KIOSK-SELFTEST-OK" "${SELFTEST_CRED[@]}" $(uefi_args iso-uefi) -cdrom "$ISO" -boot d
}

test_install() {
    local disk="$TEST_DIR/disk.img"
    rm -f "$disk"; qemu-img create -f qcow2 "$disk" 8G >/dev/null
    # Unattended install: boot the ISO's kernel directly with installer parameters.
    run_qemu install "KIOSK-INSTALL-OK" \
        -kernel "$RELEASE/vmlinuz" -initrd "$RELEASE/initrd.img" \
        -append "$(tr -d '\n' < "$REPO_DIR/boot/cmdline.txt") live-media-path=/live kiosk.installer=/dev/vda kiosk.installer.after=poweroff console=ttyS0,115200n8" \
        -cdrom "$ISO" -drive file="$disk",if=virtio,format=qcow2
    # Boot the installed disk via UEFI (shim -> grub -> slot a) ...
    # shellcheck disable=SC2046
    run_qemu installed-uefi "KIOSK-SELFTEST-OK slot=a" "${SELFTEST_CRED[@]}" $(uefi_args installed-uefi) \
        -drive file="$disk",if=virtio,format=qcow2
    # ... and via legacy BIOS (grub i386-pc in the BIOS boot partition).
    run_qemu installed-bios "KIOSK-SELFTEST-OK slot=a" "${SELFTEST_CRED[@]}" \
        -drive file="$disk",if=virtio,format=qcow2
}

test_rpi() {
    local code vars disk="$TEST_DIR/rpi.qcow2"
    QEMU=qemu-system-aarch64
    MACHINE=(-machine virt -device virtio-gpu-pci -device qemu-xhci -device usb-kbd)
    accel=(-accel tcg -cpu max)   # TCG: hosted arm64 runners have no /dev/kvm
    [[ -w /dev/kvm ]] && accel=(-accel kvm -cpu host)
    code="$(ls /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/edk2/aarch64/QEMU_EFI.fd 2>/dev/null | head -1 || true)"
    [[ -n "$code" ]] || die "arm64 UEFI firmware not found (install qemu-efi-aarch64)"
    # pflash units must be exactly 64 MiB on virt.
    cp "$code" "$TEST_DIR/rpi.code.fd"; truncate -s 64M "$TEST_DIR/rpi.code.fd"
    vars="$TEST_DIR/rpi.vars.fd"; rm -f "$vars"
    if [[ -f /usr/share/AAVMF/AAVMF_VARS.fd ]]; then cp /usr/share/AAVMF/AAVMF_VARS.fd "$vars"; fi
    truncate -s 64M "$vars"
    # Work on a copy-on-write overlay: GRUB writes grubenv, the image stays pristine.
    rm -f "$disk"; qemu-img create -q -f qcow2 -F raw -b "$RPI_IMG" "$disk" 4G
    TIMEOUT="${BOOT_TIMEOUT_RPI:-1500}"
    run_qemu rpi-uefi "KIOSK-SELFTEST-OK slot=a" "${SELFTEST_CRED[@]}" \
        -drive if=pflash,format=raw,readonly=on,file="$TEST_DIR/rpi.code.fd" \
        -drive if=pflash,format=raw,file="$vars" \
        -drive file="$disk",if=virtio,format=qcow2
}

case "${1:-all}" in
    iso-bios) test_iso_bios ;;
    iso-uefi) test_iso_uefi ;;
    install)  test_install ;;
    all)      test_iso_bios; test_iso_uefi; test_install ;;
    rpi)      test_rpi ;;
    *) die "usage: $0 {iso-bios|iso-uefi|install|all|rpi}" ;;
esac
