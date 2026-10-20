# Configuration reference (`kiosk.conf`)

Format: `KEY=value`, one per line, `#` comments, optional single or double quotes around the value.
Only keys starting with `KIOSK_` plus `UPDATE_URL`/`UPDATE_CHANNEL` are accepted.

| Key | Default | Meaning |
|---|---|---|
| `KIOSK_URL` | empty | Empty: opens `https://www.google.com/` with address bar and tabs. Set a start URL (`http(s)://` or `file://`) to use kiosk mode with `KIOSK_MODE=auto`. Also settable via kernel parameter `kiosk.url=` |
| `KIOSK_MODE` | `auto` | `auto`: kiosk only when a URL is set; `browser`: always show browser controls; `kiosk`: always hide controls. Also settable via kernel parameter `kiosk.mode=` |
| `KIOSK_LANG` | `de` | Browser UI language |
| `KIOSK_KEYMAP` | `de` | XKB layout, optional variant after a colon (`ch:de_nodeadkeys`) |
| `KIOSK_SCALE` | `1` | Device scale factor (1, 1.25, 1.5, 2) |
| `KIOSK_FRESH_PROFILE` | `1` | Delete the browser profile on every browser start |
| `KIOSK_INCOGNITO` | `0` | Incognito / private window |
| `KIOSK_ALLOW_ZOOM` | `0` | Allow pinch zoom |
| `KIOSK_PRINTING` | `0` | Allow printing |
| `KIOSK_DOWNLOADS` | `0` | Allow downloads |
| `KIOSK_MEDIA_CAPTURE` | `0` | Camera/microphone allowed for the start URL's origin without prompt |
| `KIOSK_AUTOPLAY` | `1` | Media autoplay without user gesture |
| `KIOSK_URL_ALLOWLIST` | | Space-separated Chrome URL patterns that may be visited (use with blocklist `*`) |
| `KIOSK_URL_BLOCKLIST` | | Space-separated Chrome URL patterns to block |
| `KIOSK_BROWSER_ARGS` | | Extra command line flags for the browser |
| `KIOSK_HOSTNAME` | `kiosk` | Host name |
| `KIOSK_TIMEZONE` | `Europe/Berlin` | Olson time zone |
| `KIOSK_NTP_SERVER` | | NTP server(s) for systemd-timesyncd |
| `KIOSK_WAIT_NETWORK` | `20` | Seconds to wait for connectivity before starting the browser |
| `KIOSK_WIFI_SSID` | | Wi-Fi network; empty = Ethernet/DHCP only |
| `KIOSK_WIFI_PSK` | | WPA2/WPA3 passphrase; empty with SSID set = open network |
| `KIOSK_UPDATE` | `1` | Enable OS updates (installed systems) |
| `KIOSK_UPDATE_REBOOT` | `1` | Reboot automatically after a nightly update |
| `UPDATE_URL` | from `build.conf` | Base URL for `manifest.json` and files |
| `KIOSK_SSH_AUTHORIZED_KEYS` | | Public keys (`;`-separated) for root SSH access; enables sshd |
| `KIOSK_ROOT_PASSWORD` | | Sets a root password and starts a login shell on tty2 |
| `KIOSK_DEBUG` | `0` | Allow VT switching (Ctrl+Alt+F2) and start a shell on tty2. Also `kiosk.debug=1` on the kernel command line |

## Network files

A `network/` directory next to `kiosk.conf` may contain NetworkManager keyfiles
(`*.nmconnection`) for static IPs, VLANs, 802.1X or several Wi-Fi networks. They are copied
into `/etc/NetworkManager/system-connections/` at boot. Example static Ethernet:

```ini
[connection]
id=lan
type=ethernet
autoconnect=true

[ipv4]
method=manual
addresses=192.168.1.50/24,192.168.1.1
dns=192.168.1.1;

[ipv6]
method=auto
```

## Where to put the file

| Boot mode | Location |
|---|---|
| ISO / USB written with `dd` (read-only) | `config/kiosk.conf` in the repo at build time, or a `KIOSKCFG`-labelled USB stick, or `kiosk.url=` in the boot menu (press `e`) |
| Installed (`kiosk-install`) | root of the `KIOSK_EFI` partition (FAT32) |
| Virtual machines / provisioning | systemd credential `kiosk.conf`, e.g. QEMU `-smbios type=11,value=io.systemd.credential.binary:kiosk.conf=<base64>` |
