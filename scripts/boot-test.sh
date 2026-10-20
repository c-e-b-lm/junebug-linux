#!/usr/bin/env bash
# Boot smoke tests in QEMU. Each test boots, waits for the in-image self test to print
# KIOSK-SELFTEST-OK on the serial port, then powers off.
#   boot-test.sh iso-bios      boot the ISO via isolinux (SeaBIOS)
#   boot-test.sh iso-uefi      boot the ISO via shim+grub (OVMF)
#   boot-test.sh install       install to a virtual disk from the ISO, then boot the disk (UEFI + BIOS)
#   boot-test.sh all
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_conf
require_tools qemu-system-x86_64 qemu-img timeout
RELEASE="$OUT_DIR/release"
TEST_DIR="$OUT_DIR/test"
ISO="$RELEASE/$IMAGE_NAME.iso"
[[ -s "$ISO" ]] || die "ISO missing: $ISO"
mkdir -p "$TEST_DIR"
TIMEOUT="${BOOT_TIMEOUT:-600}"
MEM="${QEMU_MEM:-2048}"

OVMF_CODE="$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd 2>/dev/null | head -1 || true)"
OVMF_VARS="$(ls /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd 2>/dev/null | head -1 || true)"

accel=(-accel tcg)
[[ -w /dev/kvm ]] && accel=(-accel kvm -cpu host)

# Credentials are passed via SMBIOS (systemd picks them up as system credentials).
SELFTEST_CRED=(-smbios "type=11,value=io.systemd.credential:kiosk.selftest=1")

run_qemu() { # name, expected-marker, qemu args...
    local name="$1" marker="$2"; shift 2
    local serial="$TEST_DIR/$name.serial.log"
    : > "$serial"
    log "qemu [$name] (timeout ${TIMEOUT}s)"
    set +e
    timeout --foreground "$TIMEOUT" qemu-system-x86_64 \
        "${accel[@]}" -m "$MEM" -smp 2 -display none -vga std \
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

case "${1:-all}" in
    iso-bios) test_iso_bios ;;
    iso-uefi) test_iso_uefi ;;
    install)  test_install ;;
    all)      test_iso_bios; test_iso_uefi; test_install ;;
    *) die "usage: $0 {iso-bios|iso-uefi|install|all}" ;;
esac
