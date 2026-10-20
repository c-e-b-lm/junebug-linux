# Updates (A/B slots with trial boot)

Installed systems keep two copies of the OS on the `KIOSK_DATA` partition: `live/a` and `live/b`.
GRUB (`boot/grub-installed.cfg`) reads three variables from `grubenv` on the ESP:

| Variable | Meaning |
|---|---|
| `slot` | slot to boot (`a` or `b`) |
| `trial` | `1` = this slot is freshly updated and not yet confirmed |
| `tried` | `1` = GRUB already booted the trial slot once |

Flow:

1. `kiosk-update` (timer: 15 min after boot without reboot, nightly 03:00 with reboot)
   downloads `manifest.json` + `manifest.json.minisig` from `UPDATE_URL`
   (default `https://github.com/<owner>/<repo>/releases/latest/download`).
2. The signature is verified against `/etc/kiosk/update.pub` (minisign). `dist` and `channel`
   must match, the version must be newer (`sort -V`). Downgrades are never applied.
3. Files (`filesystem.squashfs`, `vmlinuz`, `initrd.img`) are downloaded with resume support
   into the inactive slot, SHA-256 verified, then renamed into place. Already present files with
   the right hash are reused.
4. `grubenv` is set to `slot=<other> trial=1 tried=0`.
5. On the next boot GRUB sees `trial=1, tried=0`, sets `tried=1` and boots the new slot.
6. `kiosk-mark-good.service` waits 90 s; if `kiosk.service` is active and a browser process
   exists it sets `trial=0 tried=0`: the update is confirmed.
7. If the new slot never confirms (kernel panic, no browser, power cut before confirmation),
   GRUB finds `trial=1, tried=1` on the following boot, flips `slot` back and boots the old
   version. The failed download stays in the other slot and will be replaced by the next release.

Manual control:

```sh
kiosk-status                 # versions, slots, grubenv
kiosk-update --check         # is there a newer release?
kiosk-update --force         # re-stage the latest release even if versions match
kiosk-rollback --reboot      # boot the other slot
```

Images booted from the ISO (or a `dd`-written stick) are read-only and do not update; the
updater logs that and exits. Install to disk (`kiosk-install`) to get updates.

## Security notes

- The manifest signature is the trust anchor; GitHub HTTPS is only the transport. Anyone who can
  publish a GitHub release still cannot push an update without the minisign secret key.
- The public key is built into the image. Rotating it means shipping the new key in a release
  signed with the old key first.
- The rootfs is read-only squashfs; SSH is off unless a key is configured; root is locked.
