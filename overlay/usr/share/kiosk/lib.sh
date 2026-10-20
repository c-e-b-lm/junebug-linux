#!/bin/bash
# Shared helpers for the kiosk-* tools. Source, do not execute.

KIOSK_RUN=/run/kiosk
KIOSK_CONFIG="$KIOSK_RUN/config"
# shellcheck disable=SC2034  # used by sourcing scripts
KIOSK_ENV="$KIOSK_RUN/env"
# shellcheck disable=SC2034  # used by kiosk-update
KIOSK_PUBKEY=/etc/kiosk/update.pub

kiosk_log()  { logger -t "${KIOSK_TAG:-kiosk}" -- "$*"; printf '%s\n' "$*" >&2; }
kiosk_die()  { kiosk_log "ERROR: $*"; exit 1; }

# Value of key=value on the kernel command line, empty if absent. "key" alone yields "1".
kiosk_cmdline_get() {
    local key="$1" word
    for word in $(cat /proc/cmdline); do
        case "$word" in
            "$key") echo 1; return 0 ;;
            "$key="*) echo "${word#*=}"; return 0 ;;
        esac
    done
    return 1
}

# Load merged configuration written by kiosk-config (single-quoted, safe to source).
kiosk_load_config() {
    # shellcheck disable=SC1090
    [[ -r "$KIOSK_CONFIG" ]] && source "$KIOSK_CONFIG"
    # shellcheck disable=SC1091
    source /etc/kiosk/release
}

kiosk_slot()       { kiosk_cmdline_get kiosk.slot; }
kiosk_other_slot() { [[ "$1" == "a" ]] && echo b || echo a; }

# Mount point of the data partition (slots). Prefers the live medium when it is that partition.
kiosk_data_mount() {
    local mnt=/run/kiosk/data dev
    if mountpoint -q /run/live/medium && [[ "$(lsblk -no LABEL "$(findmnt -no SOURCE /run/live/medium)" 2>/dev/null)" == "KIOSK_DATA" ]]; then
        echo /run/live/medium; return 0
    fi
    if mountpoint -q "$mnt"; then echo "$mnt"; return 0; fi
    dev="$(blkid -L KIOSK_DATA 2>/dev/null)" || return 1
    mkdir -p "$mnt" && mount -o rw "$dev" "$mnt" && echo "$mnt"
}

# Make the data mount writable / read-only again (live-boot mounts the medium read-only).
kiosk_data_rw() { mount -o remount,rw "$1"; }
kiosk_data_ro() { [[ "$1" == /run/live/medium ]] && mount -o remount,ro "$1" 2>/dev/null; return 0; }

# Mount the ESP (KIOSK_EFI) of the disk that holds the data partition at /run/kiosk/esp (rw).
kiosk_esp_mount() {
    local mnt=/run/kiosk/esp data ddev disk esp
    if mountpoint -q "$mnt"; then echo "$mnt"; return 0; fi
    data="$(kiosk_data_mount)" || return 1
    ddev="$(findmnt -no SOURCE "$data")"
    disk="$(lsblk -no PKNAME "$ddev" | head -1)"
    esp="$(lsblk -nrpo PATH,PARTLABEL "/dev/$disk" | awk '$2=="KIOSK_EFI"{print $1; exit}')"
    [[ -n "$esp" ]] || esp="$(blkid -L KIOSK_EFI 2>/dev/null)" || return 1
    mkdir -p "$mnt" && mount -o rw,umask=022 "$esp" "$mnt" && echo "$mnt"
}

kiosk_grubenv() { # grubenv path on the ESP
    local esp; esp="$(kiosk_esp_mount)" || return 1
    echo "$esp/boot/grub/grubenv"
}

kiosk_browser_running() {
    pgrep -u kiosk -f 'google-chrome|/chromium|/firefox' >/dev/null 2>&1
}
