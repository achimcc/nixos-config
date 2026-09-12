# Nitrokey 3 für LUKS-Entsperrung und Anmeldung

**Datum:** 2026-09-12
**Status:** Entwurf, wartet auf Freigabe

## Ziel

Ein neu gekaufter Nitrokey 3 (Ersatz für den 2026-05 defekt gegangenen Vorgänger) soll
zwei Aufgaben übernehmen:

1. **LUKS-Entsperrung der Root-Partition beim Boot** — FIDO2 mit PIN und Berührung.
2. **Anmeldung und Sperrbildschirm** — FIDO2 mit PIN und Berührung statt Passwort.

In beiden Fällen bleibt ein **Passwort-Rückfallweg** bestehen, für den Fall dass der Stick
verloren geht oder erneut ausfällt. Beide Geheimnisse — LUKS-Passphrase und Benutzerpasswort —
werden bei dieser Gelegenheit neu und stark gesetzt.

## Ist-Zustand (gemessen, nicht aus der Konfiguration gelesen)

| Sache | Befund | Wie gemessen |
|---|---|---|
| Nitrokey am Bus | `20a0:42b2`, „Nitrokey 3", **keine** USB-Seriennummer | `/sys/bus/usb/devices/3-5/{idVendor,idProduct,serial}` |
| Schnittstellen | `0b:00:00` (CCID) und `03:00:00` (HID/FIDO2), sonst keine | `/sys/bus/usb/devices/3-5/descriptors`, selbst geparst |
| USBGuard | **`authorized = 0`** — Stick komplett abgeschaltet | `/sys/bus/usb/devices/3-5/authorized` |
| `/dev/hidraw*` | nur Touchpad und Touchscreen, kein Nitrokey, Rechte `root:root 0600` | `/sys/class/hidraw/*/device/uevent` |
| TPM2-Slot auf Root | **existiert**, Slot 1, wird automatisch erneuert | `journalctl -u tpm2-reenroll`: „New TPM2 token enrolled as key slot 1" für `fcef0557…` |
| Kernel-Lockdown | `lockdown=integrity` | `configuration.nix:51` |
| Initrd-HID-Module | `usbhid`, `hid_generic` vorhanden | `hardware-configuration.nix:12` |
| Konsolenlayout | `console.keyMap = "us"` | `modules/desktop.nix:107` |
| Benutzerkonto | kein `hashedPassword`, `mutableUsers` auf Standard `true` | `configuration.nix:169` |

### Warum heute nichts funktioniert

Der Ausbau-Commit `4c58b34` („Hardware-Token defekt → komplette Entfernung") hat die
USBGuard-Allow-Regeln für `20a0:42b2` mit entfernt. Zusammen mit
`implicitPolicyTarget = "block"` bedeutet das: Der Stick steckt, ist aber nicht autorisiert,
hat keine Schnittstellen, keinen Treiber und kein `hidraw`-Gerät. Kein FIDO2-Werkzeug kann
ihn sehen. Das ist die erste und wichtigste Schicht.

### Zwei Mängel im Altbestand, die dabei aufgefallen sind

**(a) Die alte USBGuard-Regel konnte nie greifen.** Sie lautete
`allow id 20a0:42b2 serial "FBB05172A161F45090A2AA9E355E0789"`. Der USB-Deskriptor des
Nitrokey 3 führt aber **gar keine Seriennummer** (gemessen: Feld leer). Die Nummer aus
`nitropy nk3 list` ist eine andere Größe und für USBGuard unsichtbar. Gewirkt hat allein die
Fallback-Zeile darunter, die im Kommentar als „TODO: nach Verifikation entfernen" markiert war.

**(b) `nouserok = true` zusammen mit `control = "sufficient"` war ein Loch.** `pam_u2f` meldet
mit `nouserok` **Erfolg**, wenn die Zuordnungsdatei fehlt, unlesbar oder fehlerhaft ist. Bei
`sufficient` beendet ein Erfolg den PAM-Stack positiv — also Anmeldung ohne jeden Faktor,
sobald die Datei wegfällt. Der Kommentar begründete `nouserok` mit dem Passwort-Rückfall;
dafür braucht man es nicht: Bei `sufficient` führt ein *Fehlschlag* des Moduls dazu, dass der
Stack weiterläuft und `pam_unix` das Passwort erfragt. Das ist genau das gewünschte Verhalten.

## Entscheidungen

| Frage | Entscheidung | Begründung |
|---|---|---|
| FIDO2 mit oder ohne PIN | **mit PIN**, an beiden Stellen | Ein gefundener Stick allein öffnet nichts |
| TPM2-Slot auf Root | **entfernen** | Nur so schützt der Stick beim Boot tatsächlich; sonst entsperrt die Platte weiter von allein und FIDO2 wäre bloß eine kürzere Eingabe |
| TPM2-Slot auf Swap | **bleibt** | Sonst zweite Berührung beim Aufwachen aus dem Ruhezustand |
| PAM-Kontrollwort | `sufficient` | Stick **oder** Passwort, nie beides nötig |
| `nouserok` | **nicht setzen** | Siehe Mangel (b) |
| Zuordnungsdatei | SOPS, root-eigen | Repo ist öffentlich; und der Benutzer soll sich für `sudo` nicht selbst einen Schlüssel eintragen können |
| `pynitrokey` | **nicht** installieren | Zieht `python-ecdsa` mit CVE-2024-23342 nach, das dafür wieder in `permittedInsecurePackages` müsste. Für FIDO2 reicht `libfido2` |

## Änderungen

### `modules/security.nix`

- **USBGuard-Regel** (bereits eingetragen, noch nicht aktiv):
  `allow id 20a0:42b2 name "Nitrokey 3" with-interface { 0b:00:00 03:00:00 } with-connect-type "hotplug"`
  Kein `serial`-Match, weil es keine gibt. Die Interface-Bindung sorgt dafür, dass ein
  BadUSB-Klon mit gleicher VID:PID, der sich zusätzlich als Tastatur ausgibt (`03:01:01`),
  nicht matcht.
- **`security.pam.u2f`** neu:
  `enable = true`, `control = "sufficient"`, `settings = { cue = true; pinverification = 1; authfile = config.sops.secrets."u2f/mappings".path; }`.
  Ausdrücklich **ohne** `nouserok`.
- **`u2fAuth = true`** für `gdm-password` (Anmeldung *und* GNOME-Sperrbildschirm), `login`
  (Textkonsole) und `sudo`.

### `configuration.nix`

- `hardware.nitrokey.enable = true` — setzt die udev-Regeln und legt die Gruppe `nitrokey` an.
- Benutzer um Gruppe `nitrokey` ergänzen (`extraGroups`), sonst bleibt `/dev/hidraw*` unlesbar.
- `boot.initrd.luks.devices."luks-fcef0557-…".crypttabExtraOpts = [ "fido2-device=auto" ]`.
- Den Kommentarblock „FIDO2-Slot ENTFERNT — Hardware-Token nicht mehr genutzt" ersetzen.
- `lockdown=integrity` bleibt unverändert — `confidentiality` würde USB-HID im Initrd
  blockieren und FIDO2 unmöglich machen.

### `modules/secureboot.nix` — **sicherheitskritisch**

Der Dienst `tpm2-reenroll` läuft heute über **beide** LUKS-Geräte:

```bash
for DEV in "$ROOT_DEV" "$SWAP_DEV"; do
  systemd-cryptenroll --wipe-slot=tpm2 "$DEV"
  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7+11 "$DEV"
```

Würde man den TPM2-Slot der Root-Partition nur von Hand löschen, **legte dieser Dienst ihn beim
nächsten Kernel-Update wieder an** — ohne Fehlermeldung. Die Eigenschaft „Boot verlangt den
Stick" wäre lautlos wieder weg. Die Schleife muss deshalb auf das Swap-Gerät eingeschränkt
werden, mit Kommentar, warum Root dort nicht mehr auftaucht.

### `secrets/secrets.yaml` und `modules/sops.nix`

Neues Feld `u2f/mappings` mit der Zuordnungszeile aus `pamu2fcfg`, als `sops.secrets` mit
`mode = "0400"` und `owner = "root"` eingebunden. Der PAM-Stack liest daraus über
`settings.authfile`.

### Aufräumen

`~/.config/Yubico/u2f_keys` und `u2f_keys.old` (Januar/Februar 2026) löschen — die
Credentials darin gehören dem defekten Stick und sind wertlos.

### `docs/TPM-ENROLLMENT.md`

Nachziehen: Root wird dort künftig nicht mehr per TPM2 entsperrt.

## Unvermeidbar manuelle Schritte

Deklarativ geht das meiste, aber drei Dinge leben im LUKS-Header beziehungsweise im Stick
selbst und sind damit Zustand, kein Code:

1. **FIDO2-PIN auf dem Stick setzen** — `fido2-token -S <gerät>`
2. **FIDO2-Credential für PAM erzeugen** — `pamu2fcfg`, Ergebnis wandert nach SOPS
3. **LUKS-Slots** — FIDO2 enrollen, neue Passphrase setzen, TPM2-Slot löschen

Diese Schritte werden im Umsetzungsplan als Befehle mit jeweils zugehörigem
Verifikationsbefehl festgehalten.

## Reihenfolge und Verifikation

Grundregel: **Kein alter Zugangsweg wird entfernt, bevor der neue nachweislich trägt.**
Jeder Schritt hat eine Messung, die den *Zustand* prüft, nicht den Rückgabewert.

| # | Schritt | Verifikation |
|---|---|---|
| 1 | `nixos-rebuild switch`, Stick neu stecken | `/sys/…/authorized` ist `1`, ein `/dev/hidraw*` gehört dem Nitrokey, `fido2-token -L` listet ihn |
| 2 | FIDO2-PIN setzen | `fido2-token -I` zeigt `clientPin: true` |
| 3 | PAM-Credential erzeugen, nach SOPS, `switch` | **In zweiter TTY testen** (`Strg+Alt+F2`), während die laufende Sitzung offen bleibt: `sudo -k; sudo true` fragt nach PIN und Berührung |
| 4 | Sperrbildschirm prüfen | Bildschirm sperren, PIN-Abfrage muss erscheinen — **siehe Risiko unten** |
| 5 | LUKS-FIDO2-Slot auf Root anlegen | `cryptsetup luksDump` zeigt ein `systemd-fido2`-Token; **Neustart als echter Test**, alte Passphrase noch intakt |
| 6 | Neue LUKS-Passphrase: neuen Slot anlegen, **prüfen**, dann alten löschen | `cryptsetup open --test-passphrase` mit der neuen Passphrase |
| 7 | Benutzerpasswort neu (`passwd`) | Abmelden und neu anmelden |
| 8 | `tpm2-reenroll` auf Swap beschränken, `switch`, **dann** TPM2-Slot auf Root löschen | `cryptsetup luksDump` zeigt kein `systemd-tpm2`-Token mehr; nach dem nächsten Kernel-Update erneut prüfen, dass es nicht zurückkommt |

Schritt 8 kommt bewusst zuletzt und in dieser Reihenfolge: erst den Dienst entschärfen, dann
den Slot löschen. Andersherum legt der Dienst den Slot beim nächsten Rebuild wieder an.

## Geheimnisse

- **Ich erzeuge die Passphrasen nicht und bekomme sie nicht zu sehen.** Der Umsetzungsplan
  enthält einen Erzeugungsbefehl, der im eigenen Terminal auszuführen ist — **nicht** über den
  `!`-Präfix in der Claude-Sitzung, sonst steht das Geheimnis im Sitzungsprotokoll.
- **Tastaturlayout:** `console.keyMap = "us"`. Die Initrd-Abfrage läuft auf US-Layout; auf der
  deutschen ThinkPad-Tastatur sind damit `y` und `z` vertauscht und Umlaute unerreichbar. Die
  LUKS-Passphrase muss in US-Layout tippbar sein — am besten ausschließlich Kleinbuchstaben,
  Ziffern und Bindestriche.
- Die Rotation gehört nach `docs/SECRET-ROTATION-LOG.md`.

## Risiken und offene Punkte

**PIN-Abfrage im GNOME-Sperrbildschirm — vom Benutzer bestätigt (2026-09-12).** Mit dem
Vorgängerstick funktionierte das Entsperren des Sperrbildschirms per FIDO2 mit PIN
nachweislich. Da sich an gnome-shell und am PAM-Dienst `gdm-password` nichts Grundsätzliches
geändert hat, ist damit kein offenes Risiko mehr, sondern eine Erwartung mit Vorgeschichte.
Schritt 4 bleibt als Messung bestehen — er bestätigt dann nur noch, statt zu erkunden.

**Bekannte Eigenart des Sticks.** Laut `~/.claude/CLAUDE.md` sperrt der Nitrokey 3A Mini sein
FIDO2-Interface nach einem gescheiterten `ssh-sign`, bis er einmal aus- und wieder eingesteckt
wird. Wenn die Anmeldung plötzlich nicht mehr geht, ist das der erste Verdacht — nicht die
Konfiguration.

**Aussperr-Risiko.** Schritte 5 bis 8 fassen die Boot-Kette an. Vor Schritt 5 sollte ein
Rettungsmedium bereitliegen und die neue Passphrase notiert sein. Ein Header-Backup der
Root-Partition (`cryptsetup luksHeaderBackup`) ist vor Schritt 6 sinnvoll — es enthält die
Slots und gehört entsprechend behandelt.

**Swap trägt die Ruhezustandsabbilder.** Er bleibt bei TPM2 mit PCR 0+7+11, entsperrt also
beim Boot des echten, signierten Systems automatisch — auch dann, wenn Root gerade auf den
Stick wartet. Das Abbild enthält Hauptspeicherinhalte. Der Schutz besteht darin, dass PCR 11
an das Lanzaboote-UKI gebunden ist und ein manipulierter Kernel den Slot nicht öffnet.
Bewusst so belassen, weil FIDO2 auf Swap eine zweite Berührung je Start bedeutete.

**Optional, nicht Teil dieses Umbaus:** `tpm2-reenroll` hing am Swap-Gerät nachweislich
**drei Tage** (`journalctl`: 8,6 s Rechenzeit auf 2 d 21 h Laufzeit, 29.08. bis 01.09.).
`systemd-cryptenroll` wartet dort auf eine Passphrase, die im Dienstkontext niemand liefert.
Nach diesem Umbau ist Swap das einzige verbleibende Gerät in der Schleife. Ein Gegenmittel
wäre `--unlock-tpm2-device=auto` plus `TimeoutStartSec`. Separat zu entscheiden.

## Was ausdrücklich nicht dazugehört

- SSH-Schlüssel auf dem Stick (`id_ed25519_sk`) und Git-Signierung darüber. Die CLAUDE.md
  hält fest, dass die Signierung wegen der Interface-Sperre bewusst über `~/.ssh/id_ed25519`
  läuft.
- WebAuthn im Browser (Firejail-Profile, `security.webauthn.*` in `home.nix`).
- OpenPGP/PIV über die CCID-Schnittstelle.

Alles drei ist nachrüstbar, sobald die beiden Kernaufgaben belegt laufen.
