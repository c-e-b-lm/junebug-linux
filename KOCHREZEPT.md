# Kochrezept: Junebug Linux bauen und releasen

Dieses Dokument beschreibt Schritt für Schritt, wie aus diesem Repository ein fertiges, signiertes
Release entsteht, das installierte Geräte automatisch einspielen.

## 0. Einmalige Vorbereitung (ca. 10 Minuten)

### Signierschlüssel

Updates werden nur eingespielt, wenn das `manifest.json` mit dem Release-Schlüssel signiert ist.
Der öffentliche Teil liegt im Image (`overlay/etc/kiosk/update.pub`), der private Teil muss als
GitHub-Secret hinterlegt sein.

```sh
# Neues Schlüsselpaar erzeugen (ohne Passwort, damit CI signieren kann)
minisign -G -W -p minisign.pub -s minisign.key -c "junebug-linux release signing key"
cp minisign.pub overlay/etc/kiosk/update.pub      # in das Repo übernehmen und committen
gh secret set MINISIGN_SECRET_KEY < minisign.key   # privaten Schlüssel als Secret hinterlegen
```

Den privaten Schlüssel sicher aufbewahren (Passwortmanager). Geht er verloren, muss ein neues
Schlüsselpaar in ein Release eingebaut und das auf alle Geräte verteilt werden, bevor der alte
Schlüssel abgeschaltet wird.

### Einstellungen prüfen

- `build.conf`: Browser (`chrome`), Kernelquelle (`trixie-backports`), `UPDATE_URL` (zeigt auf
  die Releases dieses Repos).
- `config/kiosk.conf`: Standard-URL, Sprache, Tastatur, Zeitzone, die auf dem ISO ausgeliefert werden.
- `packages/firmware.list`: Firmware-Umfang (kleiner = kleineres ISO).

## 1. Entwickeln und testen

Jeder Push auf `main` und jeder Pull Request baut das Image komplett (`ci.yml`):

1. `make lint`: shellcheck, actionlint, JSON-Prüfung
2. `make iso`: Debian-Bootstrap (mmdebstrap), Kernel + Firmware + Chrome, Squashfs, hybrides ISO
3. `make test-boot`: QEMU startet das ISO per BIOS und per UEFI, installiert es unbeaufsichtigt
   auf eine virtuelle Platte und bootet diese ebenfalls per UEFI und BIOS. Jeder Lauf muss
   `KIOSK-SELFTEST-OK` auf der seriellen Konsole melden (Browser läuft).

Das ISO liegt danach 7 Tage als Artefakt `junebug-ci` am Workflow-Lauf. CI-Builds sind
**nicht signiert**, installierte Geräte nehmen sie nicht als Update an.

Lokal (Debian/Ubuntu x86-64, root nötig):

```sh
make deps && make iso && make test-boot
```

Ohne root, aber mit Docker (z. B. auf einem VPS): siehe "Building with Docker" in
[docs/BUILDING.md](docs/BUILDING.md), ca. 4 Minuten auf 4 Kernen. Ein so gebautes ISO lässt sich
als **Pre-Release** veröffentlichen (Tag ohne `v`-Präfix, z. B. `dev-2026.10.20`, damit
`release.yml` nicht anspringt); Geräte ignorieren Pre-Releases.

## 2. Release erstellen

Versionen folgen CalVer: `vJAHR.MONAT.TAG`, bei mehreren Releases am Tag `vJAHR.MONAT.TAG.N`.

```sh
git checkout main && git pull
git tag -a v2026.10.20 -m "Chrome 155.0.8059.84, Kernel 7.2.9"
git push origin v2026.10.20
```

Der Tag startet `release.yml`:

1. Build und Boot-Tests wie in CI
2. `manifest.json` schreiben und mit `MINISIGN_SECRET_KEY` signieren
3. GitHub Release anlegen mit: ISO, `filesystem.squashfs`, `vmlinuz`, `initrd.img`,
   `manifest.json`, `manifest.json.minisig`, `SHA256SUMS`, `release.env`

Fertig ist das Release, sobald es unter *Releases* als "Latest" erscheint. Pre-Releases und
Drafts werden von den Geräten ignoriert (`releases/latest`).

### Automatische Releases

`auto-release.yml` läuft jeden Montag 04:17 UTC. Es vergleicht die aktuelle Chrome-Version
(Google-Repo) und Kernel-Version (trixie-backports) mit dem letzten Release. Gibt es etwas Neues,
wird automatisch ein Tag erzeugt und das Release gebaut. Manuell anstoßen: *Actions* →
*Auto release* → *Run workflow* (Option `force` baut auch ohne Änderung).

## 3. Was auf den Geräten passiert

- 15 Minuten nach dem Boot und jede Nacht um 03:00 (+ bis zu 45 Minuten Zufall) ruft
  `kiosk-update` das `manifest.json` ab und prüft die Signatur.
- Ist die Version neuer, werden Squashfs, Kernel und Initrd in den inaktiven Slot
  (`/live/a` oder `/live/b` auf `KIOSK_DATA`) geladen, per SHA-256 geprüft und der Slot in
  `grubenv` als *trial* aktiviert.
- Nachts wird danach neu gestartet (`KIOSK_UPDATE_REBOOT=1`). Läuft der Browser 90 Sekunden,
  bestätigt `kiosk-mark-good` den Slot. Bleibt die Bestätigung aus, bootet GRUB beim nächsten
  Start automatisch den alten Slot.
- `kiosk-status` zeigt Version, Slots und Update-Status; `kiosk-rollback --reboot` wechselt
  manuell zurück.

## 4. Release zurückziehen

Ein fehlerhaftes Release auf GitHub als *Pre-release* markieren oder löschen. `releases/latest`
zeigt dann wieder auf das vorherige Release; Geräte, die das fehlerhafte Release bereits haben,
bekommen beim nächsten Lauf das ältere **nicht** automatisch (Downgrades sind ausgeschlossen),
bis ein neues Release mit höherer Versionsnummer erscheint. Also: Fix bauen, neuen Tag setzen.

## 5. Checkliste pro Release

- [ ] CI auf `main` grün
- [ ] `config/kiosk.conf` und `build.conf` wie gewünscht
- [ ] Tag gesetzt und gepusht, `release.yml` grün
- [ ] Release auf GitHub als "Latest" sichtbar, `manifest.json.minisig` vorhanden
- [ ] Ein Testgerät nach dem nächsten Update-Lauf per `kiosk-status` kontrolliert
