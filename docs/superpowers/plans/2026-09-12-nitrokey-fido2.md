# Nitrokey 3 für LUKS-Entsperrung und Anmeldung — Umsetzungsplan

> **Für agentische Bearbeiter:** ERFORDERLICHE UNTER-SKILL: `superpowers:subagent-driven-development`
> (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Schritte nutzen
> Checkbox-Syntax (`- [ ]`).

**Ziel:** Ein Nitrokey 3 entsperrt die LUKS-Root-Partition beim Boot und meldet am
GNOME-Anmelde- und Sperrbildschirm an — beides FIDO2 mit PIN, mit erhaltenem und neu
gesetztem Passwort-Rückfall.

**Architektur:** Drei Schichten geben den Stick frei (USBGuard, udev, Kernel-Lockdown),
`systemd-cryptenroll` legt einen FIDO2-Slot im LUKS-Header an, `pam_u2f` hängt sich als
`sufficient` vor `pam_unix` in den PAM-Stack. Der TPM2-Slot der Root-Partition entfällt, damit
der Stick beim Boot tatsächlich verlangt wird; der Dienst, der ihn automatisch erneuert, wird
vorher auf das Swap-Gerät eingeschränkt.

**Tech-Stack:** NixOS (Flake), systemd-Initrd, Lanzaboote, `systemd-cryptenroll`, `pam_u2f`
1.4.0, `libfido2` 1.17.0, USBGuard, sops-nix.

**Spec:** `docs/superpowers/specs/2026-09-12-nitrokey-fido2-design.md`

## Fortschritt

**Stand 2026-09-13, nach dem Neustart-Test von Aufgabe 4.** Aufgabe 7 ist ungeplant zur Hälfte
vorgezogen (siehe unten). Nächster Schritt: Aufgabe 5.

| Aufgabe | Stand | Beleg |
|---|---|---|
| 1 Stick sichtbar | erledigt | `5ea0815`; `authorized=1`, `fido2-token -L` findet `20a0:42b2`, `hmac-secret` vorhanden |
| 2 FIDO2-PIN | erledigt | `fido2-token -I`: `clientPin` statt `noclientPin`, `pin retries: 8` |
| 3 Anmeldung | erledigt und getestet | `9452745`; sudo mit/ohne Stick, Sperrbildschirm mit/ohne Stick |
| 4 LUKS-FIDO2 Root | erledigt und getestet | `8273561`; Journal 2026-09-13: `Asking FIDO2 token` → Root entsperrt; Passphrase Slot 0: `cryptsetup open --test-passphrase --key-slot 0` exit 0 |
| 5–6 | offen | |
| 7 TPM2 von Root | Schritte 2, 4, 5, 6 erledigt, Schritt 7 (Neustart) offen | siehe unten |
| 8 | offen | |

**Slot-Belegung** (gemessen 2026-09-13 nach dem Neustart): Root 0 = Passphrase, 2 = FIDO2
(Token 1), **kein TPM2 mehr**. Swap 0 = Passphrase, 1 = TPM2 (Token 0, neu auf aktuellem PCR 11).

**Was beim Neustart passiert ist:** TPM2 verweigerte an beiden Geräten (PCR 11 geändert), Root
entsperrte per FIDO2, Swap per Passphrase. Danach startete `tpm2-reenroll`, **löschte den
TPM2-Slot der Root-Partition** (`--wipe-slot=tpm2` braucht keine Passphrase) und hing am
Neu-Eintragen, weil `systemd-cryptenroll` auf eine Passphrase wartete (`NotAfter` unendlich).
Dienst gestoppt, dann Aufgabe 7 Schritt 2 vorgezogen: Die Schleife läuft nur noch über Swap.
Messung am aktiven System: Root-UUID im Dienstskript 0, Swap-UUID 1. Der `switch` startete den
`failed`-Dienst erneut. Der Benutzer beantwortete die Swap-Abfrage per
`systemd-tty-ask-password-agent --query`, danach `New TPM2 token enrolled as key slot 1`,
`Result=success`.

**Header-Sicherung existiert:** `/root/luks-header-root-vor-fido2.img`, 16 MiB, `-rw------- root`,
12. Sep 16:59. Sie enthält noch den alten TPM2-Slot und die alte Passphrase der Root-Partition.
Wer sie einspielt, stellt beides wieder her. Aufgabe 5 Schritt 6 vernichtet sie.

**Neue Anforderung (2026-09-13):** Swap soll sich ebenfalls per FIDO2 entsperren lassen. Entschieden:
FIDO2 + Passphrase, eigene Berührung, PIN bleibt. Eingeplant als Aufgabe 7b. Aufgabe 5 gilt
jetzt für beide Geräte. Reihenfolge: 5 → 7b (mit beiden Neustart-Tests) → 6 → 8.

### Außerplanmäßig erledigt

- `113e157` `dns-watchdog` startete `systemd-resolved` bei jedem einzelnen Aussetzer neu und
  erzeugte damit selbst die DNS-Ausfälle. Symptom: `nix build` scheitert mit
  „Could not resolve host: cache.nixos.org". Jetzt erst nach zwei Fehlschlägen in Folge.
- `6383b8f` `SOPS_AGE_KEY_FILE` stand mit wörtlicher Tilde in `home.nix`.

### Beim Umsetzen gelernt — gilt für die restlichen Aufgaben

- **`grep` ist in der Benutzer-Shell ripgrep.** Kein `-E` (heißt dort `--encoding`), Muster als
  Argument: `… | rg -i -A3 "a|b"`.
- **`sops secrets/secrets.yaml` als Benutzer geht nicht.** Der Schlüssel in
  `~/.config/sops/age/keys.txt` passt zu keinem Empfänger in `.sops.yaml`. Editieren nur so:
  `sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml`
- **sops-nix prüft zur Bauzeit.** Ein Geheimnis muss in `secrets.yaml` stehen, *bevor* die
  Konfiguration, die darauf zeigt, baut.
- **`gdm-password` hat keinen eigenen Auth-Stack** (`auth substack login`). `u2f.enable` darauf
  erzeugt keine Zeile; Anmelde- und Sperrbildschirm laufen über `login`.
- **`nixos-rebuild switch` startet einen `failed`-Oneshot mit `WantedBy=multi-user.target` neu.**
  Einen hängenden Dienst also nicht nur stoppen, sondern vor dem `switch` entschärfen.
- **`systemctl cat <dienst>` zeigt nicht den Skriptinhalt**, nur den Store-Pfad. Messungen am Skript
  über `ExecStart=` auflösen.
- **Keine Gruppe `nitrokey`** — die udev-Regeln nutzen `uaccess`. Aufgabe 1 ist entsprechend
  berichtigt.

### Außerhalb des Auftrags gefunden, nicht behoben

- `NPM_CONFIG_PREFIX = "~/.npm-global"` in `home.nix` — derselbe Tilde-Fehler.
- Der passende Nutzerschlüssel für `.sops.yaml` fehlt (siehe oben).
- `tpm2-reenroll` hing am Swap-Gerät drei Tage (siehe „Was dieser Plan nicht tut").

## Globale Randbedingungen

- **Kein Zugangsweg wird entfernt, bevor der neue nachweislich trägt.** Jede Aufgabe endet mit
  einer Messung des *Zustands*, nicht mit einem Rückgabewert.
- **Der Benutzername steht nicht im Repo.** In Nix-Code `${id.username}`, in Kommandos
  `$env.USER`. Niemals ausgeschrieben — das Repo ist öffentlich (siehe
  `docs/superpowers/specs/2026-09-07-pii-aus-oeffentlichem-repo-entfernen-design.md`).
- **Kommandos sind Nushell** (Login-Shell). Umleitungen also `| save`, Variablen `$env.X`.
- **Geheimnisse gehören nicht in die Claude-Sitzung.** Alles, was eine Passphrase, eine PIN oder
  ein Passwort erzeugt oder anzeigt, läuft im eigenen Terminal — **nicht** über den
  `!`-Präfix. Beim Ansehen von Konfigurationsdateien Wertzeilen maskieren.
- **Aufgaben 4 bis 7 fassen die Boot-Kette an.** Vorher muss ein Rettungsmedium bereitliegen.
- **Gerätekennungen:**
  - Root: `/dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a`
  - Swap: `/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b`
  - Nitrokey: `20a0:42b2`, keine USB-Seriennummer, Schnittstellen `0b:00:00` + `03:00:00`
- **Arbeitsbaum ist nicht sauber.** In `modules/security.nix` liegt bereits eine fremde,
  nicht eingecheckte USBGuard-Regel (Intenso-Notfall-Stick), dazu Änderungen in `home.nix`,
  `modules/desktop.nix`, `modules/home/gnome-settings.nix`, `modules/home/sway.nix`. **Diese
  Dateien nie pauschal mit `git add -A` einsammeln** — immer einzelne Pfade committen.
- **Bauen vor Schalten:** `nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link`
  muss durchlaufen, bevor `nixos-rebuild switch` kommt. Bei Pipes `$env.LAST_EXIT_CODE` des
  Baubefehls prüfen, nicht den des letzten Gliedes.

---

## Dateiübersicht

| Datei | Zuständigkeit | Aufgabe |
|---|---|---|
| `modules/security.nix` | USBGuard-Regel (liegt schon im Baum), `security.pam.u2f`, PAM-Dienste | 1, 3 |
| `configuration.nix` | `hardware.nitrokey.enable`, Benutzergruppe, Pakete, LUKS-`crypttabExtraOpts` | 1, 4 |
| `modules/sops.nix` | Secret `u2f/mappings` einbinden | 3 |
| `secrets/secrets.yaml` | verschlüsselte Zuordnungszeile | 3 |
| `modules/secureboot.nix` | `tpm2-reenroll` auf Swap einschränken, dann entfernen | 7, 7b |
| `docs/TPM-ENROLLMENT.md` | Root wird nicht mehr per TPM2 entsperrt | 8 |
| `docs/SECRET-ROTATION-LOG.md` | Rotation von LUKS-Passphrase, Benutzerpasswort, FIDO2-PIN | 5, 6 |

---

## Aufgabe 1: Den Stick sichtbar machen

Heute ist er auf drei Ebenen tot: USBGuard hat ihn deautorisiert, es gibt keine udev-Regeln,
und die Werkzeuge fehlen. Diese Aufgabe macht ihn benutzbar — ohne sie kann keine
Folgeaufgabe irgendetwas messen.

**Dateien:**
- Ändern: `modules/security.nix` (USBGuard-Regel — **liegt bereits im Arbeitsbaum**)
- Ändern: `configuration.nix` (Abschnitt „BENUTZER" bei Zeile 169, Paketliste, neuer
  Hardware-Abschnitt)

**Schnittstellen:**
- Liefert: einen autorisierten Nitrokey mit lesbarem `/dev/hidraw*`, dazu die Kommandos
  `fido2-token`, `fido2-cred` (aus `libfido2`) und `pamu2fcfg` (aus `pam_u2f`) im `PATH`.
  Alle Folgeaufgaben setzen das voraus.

- [ ] **Schritt 1: Ausgangszustand messen**

```nu
cat /sys/bus/usb/devices/3-5/authorized
```

Erwartet: `0`. Falls der Pfad nicht existiert, steckt der Stick in einem anderen Port — dann
suchen:

```nu
grep -l 20a0 /sys/bus/usb/devices/*/idVendor
```

Das liefert den Pfad; in allen folgenden Befehlen `3-5` entsprechend ersetzen.

- [ ] **Schritt 2: USBGuard-Regel prüfen (nicht neu schreiben)**

Die Regel steht schon in `modules/security.nix` am Ende des `rules`-Blocks:

```
allow id 20a0:42b2 name "Nitrokey 3" with-interface { 0b:00:00 03:00:00 } with-connect-type "hotplug"
```

Nachsehen, dass sie da ist:

```nu
grep -c "20a0:42b2" modules/security.nix
```

Erwartet: `1`.

- [ ] **Schritt 3: `configuration.nix` — udev-Regeln und Gruppe**

Nach dem Bluetooth-Abschnitt einfügen:

```nix
  # ==========================================
  # NITROKEY 3
  # ==========================================
  # Setzt die udev-Regeln (nitrokey-udev-rules), die /dev/hidraw* des Sticks
  # zugänglich machen. KEINE Gruppenmitgliedschaft nötig: Die Regeln arbeiten
  # mit TAG+="uaccess", also vergibt systemd-logind den Zugriff per ACL an den
  # Benutzer der aktiven lokalen Sitzung.
  # Die USBGuard-Regel in modules/security.nix muss zusätzlich greifen —
  # USBGuard sitzt vor udev, ein deautorisiertes Gerät hat gar keine
  # Schnittstellen, an die udev eine Regel hängen könnte.
  hardware.nitrokey.enable = true;
```

**Keine Gruppe eintragen.** Ein früherer Entwurf dieses Plans wollte `"nitrokey"` in
`extraGroups` setzen. Das war falsch und beim Umsetzen aufgefallen: `hardware.nitrokey.enable`
legt in diesem nixpkgs gar keine Gruppe `nitrokey` an (`nix eval …config.users.groups.nitrokey`
schlägt fehl), und die Regeln vergeben den Zugriff über `TAG+="uaccess"` per ACL an die aktive
lokale Sitzung. Unser Gerät `20a0:42b2` steht namentlich in
`nitrokey-udev-rules/etc/udev/rules.d/41-nitrokey.rules`.

- [ ] **Schritt 4: `configuration.nix` — Werkzeuge**

In `environment.systemPackages` ergänzen:

```nix
    libfido2   # fido2-token: PIN setzen, Fähigkeiten prüfen
    pam_u2f    # pamu2fcfg: Credential für die PAM-Anmeldung erzeugen
```

`pynitrokey` bewusst **nicht** — es zieht `python-ecdsa` mit CVE-2024-23342 nach, das dafür
wieder in `permittedInsecurePackages` stehen müsste. Für FIDO2 wird es nicht gebraucht.

- [ ] **Schritt 5: Bauen**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
```

Erwartet: Exit 0, keine Ausgabe. Bei Fehler hier stoppen, nicht schalten.

- [ ] **Schritt 6: Schalten**

```nu
sudo nixos-rebuild switch --flake .#nixos
```

- [ ] **Schritt 7: Stick aus- und wieder einstecken**

Nötig, weil die USBGuard-Regel `with-connect-type "hotplug"` trägt und auf das
Einsteck-Ereignis wartet.

- [ ] **Schritt 8: Messen, dass alle drei Schichten offen sind**

```nu
cat /sys/bus/usb/devices/3-5/authorized
ls /sys/bus/usb/devices/3-5:*
fido2-token -L
```

Erwartet: `1`; zwei Schnittstellenverzeichnisse; und eine Zeile der Form
`/dev/hidrawN: vendor=0x20a0, product=0x42b2 (Nitrokey Nitrokey 3)`.

**Wenn `fido2-token -L` leer bleibt, obwohl `authorized` 1 ist:** Die ACL aus `uaccess` hängt an
der aktiven lokalen Sitzung. Prüfen, dass eine solche existiert und das Gerät die ACL trägt:

```nu
loginctl show-session (loginctl | find (whoami) | first | split row " " | first) -p Active -p Remote
getfacl /dev/hidrawN
```

Erwartet: `Active=yes`, `Remote=no`, und in der ACL ein `user:` -Eintrag mit `rw-` für die
eigene Benutzerkennung. Über SSH gibt es keine aktive lokale Sitzung — dann ist `sudo` nötig.

- [ ] **Schritt 9: hmac-secret bestätigen**

Ohne diese Erweiterung kann der Stick keinen LUKS-Slot tragen — das würde erst in Aufgabe 4
auffallen, deshalb hier schon prüfen:

```nu
fido2-token -I (fido2-token -L | split row ":" | first | str trim) | grep -i "extensions\|options"
```

Erwartet: `extensions:` enthält `hmac-secret`.

- [ ] **Schritt 10: Committen**

```nu
git add configuration.nix modules/security.nix
git commit -m "Nitrokey 3: USBGuard-Regel, udev und Werkzeuge"
```

**Achtung:** `modules/security.nix` enthält auch die fremde Intenso-Regel aus dem Arbeitsbaum.
Vor dem Commit `git diff --cached modules/security.nix` ansehen und entscheiden, ob sie
mitgehen soll — falls nicht, mit `git add -p` nur den Nitrokey-Teil aufnehmen.

---

## Aufgabe 2: FIDO2-PIN auf dem Stick setzen

Ein fabrikneuer Stick hat keine PIN. Ohne PIN sind sowohl `--fido2-with-client-pin=yes` als
auch `pinverification=1` wirkungslos beziehungsweise schlagen fehl.

**Dateien:** keine. Das ist Zustand im Stick, nicht im Repo.

**Schnittstellen:**
- Liefert: einen Stick mit gesetzter PIN. Aufgaben 3 und 4 brauchen das zwingend.

- [ ] **Schritt 1: Ausgangszustand messen**

```nu
let dev = (fido2-token -L | split row ":" | first | str trim)
fido2-token -I $dev | grep -i "clientpin\|pin"
```

Erwartet bei neuem Stick: `clientPin: false` beziehungsweise `options:` ohne gesetztes `clientPin`.

- [ ] **Schritt 2: PIN setzen — im eigenen Terminal**

**Nicht über den `!`-Präfix ausführen.** Die PIN wird zwar nicht ausgegeben, aber der Befehl
gehört zur Geheimnis-Handhabung.

```nu
fido2-token -S (fido2-token -L | split row ":" | first | str trim)
```

Fragt zweimal nach der neuen PIN. Mindestens 6 Zeichen, bei Nitrokey 3 sind auch Buchstaben
erlaubt. **Merken oder im Passwortspeicher ablegen** — nach 8 Fehlversuchen sperrt sich der
FIDO2-Teil des Sticks dauerhaft und muss zurückgesetzt werden, was alle Credentials und damit
den LUKS-Slot aus Aufgabe 4 vernichtet.

- [ ] **Schritt 3: Messen**

```nu
fido2-token -I (fido2-token -L | split row ":" | first | str trim) | grep -i clientpin
```

Erwartet: `clientPin: true`.

- [ ] **Schritt 4: Kein Commit**

Nichts im Repo geändert. Der Eintrag in `docs/SECRET-ROTATION-LOG.md` kommt gesammelt in
Aufgabe 6.

---

## Aufgabe 3: Anmeldung und Sperrbildschirm

**Dateien:**
- Ändern: `secrets/secrets.yaml` (neues Feld `u2f/mappings`)
- Ändern: `modules/sops.nix` (Secret einbinden)
- Ändern: `modules/security.nix` (`security.pam.u2f` und PAM-Dienste)

**Schnittstellen:**
- Verbraucht: gesetzte FIDO2-PIN aus Aufgabe 2.
- Liefert: `config.sops.secrets."u2f/mappings".path` — der Pfad, den `pam_u2f` als `authfile`
  liest. Keine spätere Aufgabe baut darauf auf.

- [ ] **Schritt 1: Credential erzeugen — im eigenen Terminal**

```nu
pamu2fcfg -u $env.USER -N | save --raw /tmp/u2f-mapping.txt
```

- `-u $env.USER` schreibt den Benutzernamen in die Zeile
- `-N` = `--pin-verification`: verlangt PIN-Prüfung bei jeder späteren Anmeldung

Der Stick blinkt; einmal berühren, PIN eingeben. Ergebnis ist eine Zeile
`<benutzer>:<keyhandle>,<pubkey>,es256,+presence,+pin`.

- [ ] **Schritt 2: Nach SOPS übernehmen**

```nu
sops secrets/secrets.yaml
```

Im Editor ergänzen (Inhalt aus `/tmp/u2f-mapping.txt` einfügen):

```yaml
u2f:
    mappings: <die Zeile aus pamu2fcfg>
```

Danach die Zwischendatei vernichten:

```nu
shred -u /tmp/u2f-mapping.txt
```

- [ ] **Schritt 3: Prüfen, dass es verschlüsselt im Repo liegt**

```nu
grep -c "u2f" secrets/secrets.yaml
grep -c "es256" secrets/secrets.yaml
```

Erwartet: erster Befehl ≥ 1 (der Feldname steht im Klartext), zweiter `0` — der Wert ist
verschlüsselt. Findet der zweite Befehl etwas, ist die Datei unverschlüsselt gespeichert
worden: **nicht committen**, Aufgabe abbrechen, `sops` erneut aufrufen.

- [ ] **Schritt 4: `modules/sops.nix` — Secret einbinden**

Bei den übrigen `secrets."…"`-Einträgen ergänzen:

```nix
    # FIDO2-Zuordnung für pam_u2f (Credential-Handle + öffentlicher Schlüssel).
    # Bewusst root-eigen und nicht ~/.config/Yubico/u2f_keys: Das Repo ist
    # öffentlich, und eine Datei, die der Benutzer selbst schreiben kann, hiesse
    # er könnte sich für sudo einen eigenen Schlüssel eintragen.
    secrets."u2f/mappings" = {
      mode = "0400";
      owner = "root";
    };
```

- [ ] **Schritt 5: `modules/security.nix` — PAM**

Im Abschnitt vor `security.pam.services.login.enableGnomeKeyring` einfügen:

```nix
  # ==========================================
  # FIDO2-ANMELDUNG (Nitrokey 3)
  # ==========================================
  #
  # `sufficient`: Der Stick ist ein ZUSÄTZLICHER Weg, kein Ersatz. Steckt er,
  # genügen PIN und Berührung. Steckt er nicht, schlägt pam_u2f fehl, der Stack
  # läuft weiter und pam_unix fragt das Passwort.
  #
  # KEIN `nouserok`. Es liesse pam_u2f ERFOLG melden, sobald die Zuordnungsdatei
  # fehlt oder unlesbar ist — zusammen mit `sufficient` wäre das eine Anmeldung
  # ganz ohne Faktor. Der Passwort-Rückfall braucht es nicht, der entsteht schon
  # dadurch, dass ein FEHLSCHLAG bei `sufficient` einfach weiterlaufen lässt.
  #
  # `pinverification = 1` verlangt die Stick-PIN zusätzlich zur Berührung —
  # ein gefundener Stick allein öffnet also nichts.
  security.pam.u2f = {
    enable = true;
    control = "sufficient";
    settings = {
      cue = true;             # blendet "touch your security key" ein
      pinverification = 1;
      authfile = config.sops.secrets."u2f/mappings".path;
    };
  };

  # gdm-password deckt BEIDES ab: Anmeldebildschirm und GNOME-Sperrbildschirm.
  security.pam.services.gdm-password.u2f.enable = true;
  security.pam.services.login.u2f.enable = true;   # Textkonsole
  security.pam.services.sudo.u2f.enable = true;
```

Schreibweise beachten: `services.<n>.u2f.enable`. Das alte `u2fAuth` ist nur noch ein
umbenannter Alias.

- [ ] **Schritt 6: Bauen**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
```

- [ ] **Schritt 7: Erzeugte PAM-Zeile vorab kontrollieren**

Bevor geschaltet wird, nachsehen, was tatsächlich entsteht:

```nu
nix eval --raw .#nixosConfigurations.nixos.config.security.pam.services.sudo.text | grep u2f
```

Erwartet: eine Zeile `auth sufficient …/pam_u2f.so cue pinverification=1 authfile=/run/secrets/u2f/mappings`.
**`nouserok` darf dort nicht stehen.**

- [ ] **Schritt 8: Schalten**

```nu
sudo nixos-rebuild switch --flake .#nixos
```

- [ ] **Schritt 9: Secret prüfen**

```nu
sudo ls -l /run/secrets/u2f/mappings
```

Erwartet: `-r-------- 1 root root`.

- [ ] **Schritt 10: In zweiter Konsole testen — laufende Sitzung offen lassen**

`Strg+Alt+F2`, anmelden, dann:

```nu
sudo -k
sudo true
```

Erwartet: Aufforderung zur PIN, dann Berührung, dann Erfolg **ohne** Passworteingabe.

Gegenprobe mit gezogenem Stick: derselbe Aufruf muss nach dem Passwort fragen und es
akzeptieren. **Diese Gegenprobe ist der eigentliche Test** — sie belegt den Rückfallweg.

**Wenn der Stick plötzlich nicht mehr reagiert, obwohl er eben noch ging:** Laut
`~/.claude/CLAUDE.md` sperrt der Nitrokey 3 sein FIDO2-Interface nach einem gescheiterten
`ssh-sign`, bis er einmal aus- und wieder eingesteckt wird. Erst neu stecken, dann die
Konfiguration verdächtigen.

- [ ] **Schritt 11: Sperrbildschirm testen**

Bildschirm sperren (`Super+L`), Stick eingesteckt. Erwartet: PIN-Abfrage, Berührung, entsperrt.
Mit dem Vorgängerstick funktionierte das nachweislich; es wird hier bestätigt, nicht erkundet.

Dann noch einmal sperren, Stick ziehen: das Passwort muss weiterhin entsperren.

- [ ] **Schritt 12: Committen**

```nu
git add modules/security.nix modules/sops.nix secrets/secrets.yaml
git commit -m "FIDO2-Anmeldung: pam_u2f mit PIN, Zuordnung aus SOPS"
```

---

## Aufgabe 4: FIDO2-Slot für die Root-Partition

**Dateien:**
- Ändern: `configuration.nix` (Zeilen 112–114, der Kommentarblock „FIDO2-Slot ENTFERNT")

**Schnittstellen:**
- Verbraucht: gesetzte FIDO2-PIN (Aufgabe 2), funktionierender Stick (Aufgabe 1).
- Liefert: einen `systemd-fido2`-Token im LUKS-Header der Root-Partition.

- [ ] **Schritt 1: Rettungsmedium bereitlegen**

Ein bootfähiger NixOS-Stick, an dem die aktuelle LUKS-Passphrase funktioniert. Ab hier wird die
Boot-Kette angefasst.

- [ ] **Schritt 2: Header-Sicherung anlegen**

```nu
sudo cryptsetup luksHeaderBackup /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a --header-backup-file /root/luks-header-root-vor-fido2.img
sudo chmod 600 /root/luks-header-root-vor-fido2.img
```

**Diese Datei ist so wertvoll wie die Platte.** Sie enthält alle Slots; wer sie und die
zugehörige Passphrase hat, entschlüsselt die Platte. In Aufgabe 5 wird sie vernichtet, weil sie
danach die *alte* Passphrase wieder gültig machen würde.

- [ ] **Schritt 3: Ausgangszustand messen**

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a
```

Notieren: welche Keyslots belegt sind und welche Tokens existieren. Erwartet nach bisherigem
Befund: ein Passphrase-Slot und ein `systemd-tpm2`-Token auf Slot 1.

- [ ] **Schritt 4: `configuration.nix` anpassen**

Den Kommentarblock bei Zeile 112 ersetzen durch:

```nix
  # Root-Partition: FIDO2-Entsperrung per Nitrokey 3 (PIN + Berührung),
  # Passphrase bleibt als Rückfall.
  #
  # Voraussetzungen, die anderswo stehen und nicht angetastet werden dürfen:
  # - lockdown=integrity (oben in boot.kernelParams). "confidentiality" würde
  #   USB-HID im Initrd blockieren und FIDO2 unmöglich machen.
  # - usbhid/hid_generic im Initrd (hardware-configuration.nix).
  # - boot.initrd.systemd.fido2.enable ist standardmäßig true.
  #
  # ENROLLMENT (einmalig, siehe docs/superpowers/plans/2026-09-12-nitrokey-fido2.md):
  #   sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes \
  #     /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a
  boot.initrd.luks.devices."luks-fcef0557-8a09-4f30-b78e-aecc458a975a" = {
    crypttabExtraOpts = [ "fido2-device=auto" ];
  };
```

**Nicht** `device = …` ergänzen — das steht schon in `hardware-configuration.nix:21`, und Nix
führt beide Definitionen zusammen.

- [ ] **Schritt 5: Bauen und schalten**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#nixos
```

- [ ] **Schritt 6: Slot anlegen**

```nu
sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a
```

Fragt zuerst die **aktuelle LUKS-Passphrase** ab (zum Entsperren des Headers), dann die
**FIDO2-PIN**, dann Berührung.

- [ ] **Schritt 7: Messen**

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a | grep -A4 -i "systemd-fido2"
```

Erwartet: ein Token vom Typ `systemd-fido2` mit zugeordnetem Keyslot.

- [ ] **Schritt 8: Neustart — der eigentliche Test**

```nu
sudo reboot
```

Erwartet beim Hochfahren: Aufforderung, den Stick zu berühren und die PIN einzugeben. Die
Passphrase muss weiterhin funktionieren (mit Esc oder nach Zeitablauf durchschalten).

**Wenn FIDO2 im Initrd nicht greift:** Passphrase eingeben, hochfahren, dann
`journalctl -b -u systemd-cryptsetup@*` ansehen. Häufigste Ursache ist, dass der Stick in einem
Port steckt, dessen Controller im Initrd noch nicht bereit ist — anderen Port probieren.

- [ ] **Schritt 9: Committen**

```nu
git add configuration.nix
git commit -m "Root-LUKS: FIDO2-Slot fuer den Nitrokey 3, Passphrase bleibt Rueckfall"
```

---

## Aufgabe 5: Neue LUKS-Passphrase für Root und Swap

**Überarbeitet 2026-09-13.** Das Rückfallpasswort gilt jetzt für **beide** Geräte. Eine Passphrase
ist nur einmal aufzuschreiben. `systemd-cryptsetup` merkt sich eine eingegebene Passphrase und
probiert sie am zweiten Gerät; beim Neustart-Test wird gemessen, ob sie wirklich nur einmal
abgefragt wird. Den Neustart-Test übernimmt Aufgabe 7b.

**Dateien:**
- Ändern: `docs/SECRET-ROTATION-LOG.md`

**Schnittstellen:**
- Verbraucht: funktionierenden FIDO2-Slot der Root-Partition (Aufgabe 4) als zweiten Weg.
- Liefert: die neue Passphrase, mit der Aufgabe 7b den FIDO2-Slot am Swap-Gerät anlegt.

- [ ] **Schritt 1: Passphrase erzeugen, im eigenen Terminal, nicht über `!`**

**Layoutfest statt Diceware-Standard.** Das Initrd tippt auf `us`, die Sitzung auf
`us-umlaut,de`. Zwischen US und DE liegen `y`/`z` vertauscht, und `-` sitzt woanders. Deshalb:
nur Wörter aus `a`–`x`, Leerzeichen als Trenner. Aus der EFF-Liste (7776 Wörter) bleiben 6500,
das sind 12,67 Bit pro Wort; **8 Wörter ≈ 101 Bit**. `secrets.choice` nutzt den
Zufallsgenerator des Kernels:

```nu
python3 -c 'import secrets,re; w=[l.split("\t")[1].strip() for l in open("/nix/store/1i1nmd6p6vb4smz20ncaqprkfn3sj2ah-python3.14-diceware-1.0.1/lib/python3.14/site-packages/diceware/wordlists/wordlist_en_eff.txt")]; w=[x for x in w if re.fullmatch("[a-x]+",x)]; print(" ".join(secrets.choice(w) for _ in range(8)))'
```

Fehlt der Store-Pfad (nach einer Garbage Collection), vorher
`nix build --no-link .#nixosConfigurations.nixos.pkgs.diceware` ausführen.

Die Passphrase in den Passwortspeicher legen **und zusätzlich auf Papier**, zusammen mit dem
Rettungsmedium. Wenn Stick und Passphrase gleichzeitig weg sind, sind die Daten verloren.

- [ ] **Schritt 2: Neue Passphrase an beiden Geräten als zusätzlichen Slot anlegen**

```nu
sudo cryptsetup luksAddKey /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a
sudo cryptsetup luksAddKey /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
```

Jeweils zuerst eine **vorhandene** Passphrase (die alte des Geräts), dann zweimal die neue.

- [ ] **Schritt 3: Belegung messen und neue Passphrase prüfen, bevor der alte Slot fällt**

```nu
for dev in [fcef0557-8a09-4f30-b78e-aecc458a975a f8e58c55-8cf8-4781-bdfd-a0e4c078a70b] {
  print $"== ($dev)"
  sudo cryptsetup luksDump $"/dev/disk/by-uuid/($dev)" | rg '^\s+[0-9]+: |Keyslot:'
}
```

Erwartet: Root 0 = alt, 1 = neu, 2 = FIDO2. Swap 0 = alt, 1 = TPM2, 2 = neu. Dann für jedes Gerät
den **neuen** Slot mit der neuen Passphrase prüfen (Slot-Nummer aus der Messung):

```nu
sudo cryptsetup open --test-passphrase --key-slot <neu> /dev/disk/by-uuid/<uuid>; print $"exit=($env.LAST_EXIT_CODE)"
```

Erwartet `exit=0` an beiden. Sonst **den alten Slot nicht anfassen**.

- [ ] **Schritt 4: Alte Slots entfernen**

```nu
sudo cryptsetup luksKillSlot /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a 0
sudo cryptsetup luksKillSlot /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b 0
```

Nur mit `0`, wenn Schritt 3 den alten Slot dort gezeigt hat. Zur Bestätigung die **neue**
Passphrase eingeben.

- [ ] **Schritt 5: Messen**

Die Schleife aus Schritt 3 erneut. Erwartet: Slot 0 an beiden Geräten weg.

- [ ] **Schritt 6: Alte Header-Sicherung vernichten und neu anlegen**

Die Sicherung aus Aufgabe 4 enthält noch den **alten** Passphrase-Slot und den TPM2-Slot der
Root-Partition. Wer sie einspielt, macht beides wieder gültig:

```nu
sudo shred -u /root/luks-header-root-vor-fido2.img
sudo cryptsetup luksHeaderBackup /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a --header-backup-file /root/luks-header-root-nach-rotation.img
sudo chmod 600 /root/luks-header-root-nach-rotation.img
```

- [ ] **Schritt 7: Rotation protokollieren**

In `docs/SECRET-ROTATION-LOG.md` einen Eintrag nach vorhandenem Muster: Datum, Gegenstand
„LUKS-Passphrase Root- und Swap-Partition“, Grund „Wechsel auf Nitrokey 3, Rotation bei der
Gelegenheit“. **Kein Wert, nur die Tatsache.**

- [ ] **Schritt 8: Committen**

```nu
git add docs/SECRET-ROTATION-LOG.md
git commit -m "LUKS-Passphrase von Root und Swap rotiert"
```

---

## Aufgabe 6: Neues Benutzerpasswort

**Dateien:**
- Ändern: `docs/SECRET-ROTATION-LOG.md`

**Schnittstellen:** keine.

- [ ] **Schritt 1: Prüfen, dass das Passwort veränderlich ist**

```nu
nix eval .#nixosConfigurations.nixos.config.users.mutableUsers
```

Erwartet: `true`. Wäre es `false`, ginge es nur über `hashedPasswordFile` in der Konfiguration
— dann diese Aufgabe anhalten und neu planen.

- [ ] **Schritt 2: Passwort setzen — im eigenen Terminal, nicht über `!`**

Erzeugen wie in Aufgabe 5; hier ist das Layout egal, weil GDM das Sitzungslayout nutzt:

```nu
nix shell .#nixosConfigurations.nixos.pkgs.diceware -c diceware --no-caps --delimiter "-" --num 6
passwd
```

- [ ] **Schritt 3: Messen — in zweiter Konsole, laufende Sitzung offen lassen**

`Strg+Alt+F2`, mit dem **neuen** Passwort anmelden. Gelingt das nicht, ist die Sitzung auf
`F1` noch offen und `passwd` lässt sich wiederholen.

- [ ] **Schritt 4: Schlüsselbund prüfen**

Das GNOME-Schlüsselbund-Passwort ist an das alte Anmeldepasswort gebunden. Nach dem nächsten
vollständigen Abmelden und Anmelden prüfen:

```nu
journalctl --user -u gnome-keyring-daemon -b | tail -20
```

Fragt GNOME nach dem alten Schlüsselbund-Passwort, muss es einmal manuell auf das neue
umgestellt werden (Anwendung „Passwörter und Schlüssel", Schlüsselbund „Anmeldung",
Passwort ändern).

**Vorsicht mit dem Schlüsselbund-Wächter:** `home.nix` betreibt `gnome-keyring-guard` und
`gnome-keyring-backup` (siehe `docs/superpowers/specs/`-Umfeld und die Keyring-Notizen im
Projektgedächtnis). Der Wächter spielt bei erkannter Beschädigung ein „Golden Backup" zurück.
Nach dem Passwortwechsel deshalb prüfen, dass er nicht anschlägt:

```nu
journalctl --user -u gnome-keyring-guard -b | tail -20
```

Erwartet: kein Wiederherstellungsvorgang. Schlägt er an, ist das Sicherungsabbild noch an das
alte Passwort gebunden und muss nach erfolgreichem Wechsel neu erzeugt werden.

- [ ] **Schritt 5: Rotation protokollieren und committen**

Eintrag in `docs/SECRET-ROTATION-LOG.md`: Datum, „Benutzerpasswort" und „FIDO2-PIN Nitrokey 3
(neu gesetzt)". Keine Werte.

```nu
git add docs/SECRET-ROTATION-LOG.md
git commit -m "Benutzerpasswort rotiert, FIDO2-PIN protokolliert"
```

---

## Aufgabe 7: TPM2 von der Root-Partition entfernen

Das ist der Schritt, der den Stick beim Boot überhaupt erst notwendig macht. **Reihenfolge ist
hier sicherheitsrelevant:** erst den Dienst entschärfen, dann den Slot löschen. Andersherum
legt `tpm2-reenroll` den Slot beim nächsten Kernel-Update wieder an — lautlos, ohne Fehler.

**Dateien:**
- Ändern: `modules/secureboot.nix` (Schleife im `tpm2-reenroll`-Skript, etwa Zeile 154–176)

**Schnittstellen:**
- Verbraucht: funktionierenden FIDO2-Slot (Aufgabe 4) und die neue Passphrase (Aufgabe 5).
  **Beide müssen belegt funktionieren**, sonst gibt es nach diesem Schritt keinen Weg mehr in
  die Platte.

- [ ] **Schritt 1: Vorbedingung hart prüfen**

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a | grep -c "systemd-fido2"
```

Erwartet: mindestens `1`. Ist das `0`, **hier stoppen** — Aufgabe 4 war nicht erfolgreich.

- [ ] **Schritt 2: `modules/secureboot.nix` — Schleife auf Swap einschränken**

Ersetzen:

```bash
      # Re-Enrollment für beide LUKS-Devices.
      # --wipe-slot=tpm2 entfernt alten Slot, --tpm2-pcrs=0+7+11 enrollt neu.
      # Root-Partition:
      ROOT_DEV="/dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a"
      SWAP_DEV="/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b"

      for DEV in "$ROOT_DEV" "$SWAP_DEV"; do
```

durch:

```bash
      # Re-Enrollment NUR für das Swap-Gerät.
      #
      # Die Root-Partition steht hier bewusst NICHT mehr: Sie wird seit
      # 2026-09-12 per FIDO2 (Nitrokey 3, PIN + Berührung) oder Passphrase
      # entsperrt, nicht mehr per TPM2. Träge man sie wieder ein, legte dieser
      # Dienst beim nächsten Kernel-Update stillschweigend einen TPM2-Slot an
      # und die Platte entsperrte wieder von allein — der Sicherheitsgewinn
      # wäre weg, ohne dass irgendwo ein Fehler erschiene.
      # Siehe docs/superpowers/specs/2026-09-12-nitrokey-fido2-design.md
      SWAP_DEV="/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b"

      for DEV in "$SWAP_DEV"; do
```

- [ ] **Schritt 3: Bauen und schalten**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#nixos
```

- [ ] **Schritt 4: Messen, dass der Dienst die Root-UUID nicht mehr kennt**

```nu
let skript = (systemctl show tpm2-reenroll -p ExecStart --value | parse --regex 'path=(?<p>\S+)' | get p.0)
rg -c fcef0557 $skript
```

Erwartet: keine Ausgabe (Exit-Code 1 = null Treffer). Steht dort eine Zahl, hat der `switch` nicht
gegriffen — **nicht weitermachen**.

**Nicht** `systemctl cat tpm2-reenroll | grep -c fcef0557`: Die Unit-Datei enthält nur den
Store-Pfad des Skripts, die UUID steht im Skript selbst. Die Messung ergibt deshalb auch am
unveränderten System `0` — am 2026-09-13 so nachgewiesen.

- [ ] **Schritt 5: TPM2-Slot der Root-Partition löschen**

```nu
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a
```

- [ ] **Schritt 6: Messen**

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a | grep -c "systemd-tpm2"
```

Erwartet: `0`. **Die folgende Gegenprobe ist durch Aufgabe 7b überholt.** Swap verliert seinen
TPM2-Slot dort absichtlich. Sie gilt nur, solange 7b nicht umgesetzt ist:

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b | grep -c "systemd-tpm2"
```

Erwartet: mindestens `1`.

- [ ] **Schritt 7: Neustart — der Beweis**

```nu
sudo reboot
```

Erwartet: Die Platte entsperrt **nicht** mehr von allein. Es kommt die FIDO2-Aufforderung; ohne
Stick führt nur die neue Passphrase weiter. Genau das war das Ziel des ganzen Umbaus.

- [ ] **Schritt 8: Committen**

```nu
git add modules/secureboot.nix
git commit -m "tpm2-reenroll nur noch fuer Swap, TPM2-Slot der Root-Partition entfernt"
```

- [ ] **Schritt 9: Nachkontrolle terminieren**

Nach dem **nächsten Kernel-Update** noch einmal messen, dass der Slot wirklich weg bleibt:

```nu
sudo cryptsetup luksDump /dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a | grep -c "systemd-tpm2"
```

Erwartet weiterhin `0`. Das ist die Messung, die belegt, dass Schritt 2 gewirkt hat — vorher
ist es nur eine Behauptung.

---

## Aufgabe 7b: Swap per FIDO2 statt TPM2

**Hinzugekommen 2026-09-13** auf Wunsch des Benutzers. Entschieden: Swap wird mit FIDO2 oder
Passphrase entsperrt, **eigene Berührung, PIN bleibt**. Der TPM2-Slot am Swap-Gerät und der
Dienst `tpm2-reenroll` entfallen ganz, damit auch sein Hänger nach Kernel-Updates. Beim Start:
voraussichtlich eine PIN-Abfrage (zu messen), zwei Berührungen.

**Dateien:**
- Ändern: `configuration.nix` (Swap-Block, `crypttabExtraOpts` und Kommentar)
- Ändern: `modules/secureboot.nix` (`systemd.services.tpm2-reenroll` samt Kommentarblock entfernen)

**Schnittstellen:**
- Verbraucht: neue Passphrase an beiden Geräten (Aufgabe 5), TPM2-freie Root-Partition (Aufgabe 7).
- Liefert: ein System, das TPM2 für LUKS nicht mehr benutzt. Aufgabe 8 zieht
  `docs/TPM-ENROLLMENT.md` entsprechend nach.

- [ ] **Schritt 1: FIDO2-Slot am Swap-Gerät anlegen**

```nu
sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
```

Fragt nach der neuen Passphrase, dann nach der PIN, dann nach einer Berührung.

- [ ] **Schritt 2: `configuration.nix`: Swap auf FIDO2 schalten**

Im Swap-Block `crypttabExtraOpts = [ "tpm2-device=auto" ];` durch
`crypttabExtraOpts = [ "fido2-device=auto" ];` ersetzen und den TPM2-Kommentar (PCR-Policy,
Trade-off, Enrollment) durch einen Verweis auf den Root-Block und diesen Plan ersetzen.
`allowDiscards = false` bleibt.

- [ ] **Schritt 3: `modules/secureboot.nix`: `tpm2-reenroll` entfernen**

Den Kommentarblock „TPM2 AUTOMATISCHES RE-ENROLLMENT“ und `systemd.services.tpm2-reenroll`
vollständig löschen. Messen:

```nu
rg -n 'tpm2-reenroll|f8e58c55|fcef0557' modules/secureboot.nix
```

Erwartet: keine Treffer.

- [ ] **Schritt 4: Bauen und schalten**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#nixos
```

Messen, an der erzeugten Datei und nicht an der Option. Ein `/etc/crypttab` gibt es auf dem
laufenden System nicht, die Zeilen stehen nur im Initrd:

```nu
let ct = (nix build --no-link --print-out-paths '.#nixosConfigurations.nixos.config.boot.initrd.systemd.contents."/etc/crypttab".source' | str trim)
open --raw $ct | rg -o 'luks-[0-9a-f]{8}|\S*-device=auto'
systemctl cat tpm2-reenroll
```

Erwartet: `fido2-device=auto` bei `luks-f8e58c55` **und** bei `luks-fcef0557`, nirgends mehr
`tpm2-device`. `systemctl cat` meldet `No files found`.

- [ ] **Schritt 5: TPM2-Slot am Swap-Gerät löschen**

Erst jetzt, weil ab hier kein Dienst ihn wieder anlegt:

```nu
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
for dev in [fcef0557-8a09-4f30-b78e-aecc458a975a f8e58c55-8cf8-4781-bdfd-a0e4c078a70b] {
  print $"== ($dev)"
  sudo cryptsetup luksDump $"/dev/disk/by-uuid/($dev)" | rg '^\s+[0-9]+: |Keyslot:'
}
```

Erwartet an beiden Geräten: genau ein Passphrase-Slot, ein `systemd-fido2`-Token, kein
`systemd-tpm2`.

- [ ] **Schritt 6: Neustart mit Stick**

Erwartet: keine Passphrase-Abfrage, PIN, Berührungen. Danach aus dem Journal belegen:

```nu
journalctl -b -o short-monotonic | rg 'Asking FIDO2|Password query on|Finished Cryptography Setup|TPM'
```

Erwartet: zweimal `Asking FIDO2`, keine TPM-Zeile aus `systemd-cryptsetup`, beide
`Finished Cryptography Setup`. Die Zahl der `Password query`-Paare zeigt, wie oft die PIN
abgefragt wurde.

- [ ] **Schritt 7: Neustart ohne Stick**

Erwartet: Nach dem FIDO2-Versuch kommt die Passphrase-Abfrage, die **neue** Passphrase
entsperrt beide Geräte. Das ist zugleich Aufgabe 7 Schritt 7 und der ausstehende
Passphrase-Test beim Start aus Aufgabe 4.

- [ ] **Schritt 8: Committen**

```nu
git add configuration.nix modules/secureboot.nix
git commit -m "Swap per FIDO2 statt TPM2, tpm2-reenroll entfernt"
```

---

## Aufgabe 8: Aufräumen und Dokumentation nachziehen

**Dateien:**
- Löschen: `~/.config/Yubico/u2f_keys`, `~/.config/Yubico/u2f_keys.old`
- Ändern: `docs/TPM-ENROLLMENT.md`
- Ändern: `modules/secureboot.nix` (Kommentarblock „LUKS-Entsperrung Hierarchie")

**Schnittstellen:** keine.

- [ ] **Schritt 1: Alte Credentials wegwerfen**

Die Dateien stammen von Januar und Februar 2026 und gehören dem defekten Vorgängerstick. Sie
werden von nichts mehr gelesen — `authfile` zeigt seit Aufgabe 3 nach `/run/secrets/`:

```nu
rm ~/.config/Yubico/u2f_keys ~/.config/Yubico/u2f_keys.old
rmdir ~/.config/Yubico
```

- [ ] **Schritt 2: Messen, dass nichts mehr darauf zeigt**

```nu
nix eval --raw .#nixosConfigurations.nixos.config.security.pam.services.gdm-password.text | grep u2f
```

Erwartet: `authfile=/run/secrets/u2f/mappings`, kein Bezug auf ein Home-Verzeichnis.

- [ ] **Schritt 3: `modules/secureboot.nix` — Kommentarblock berichtigen**

Der Block „LUKS-Entsperrung Hierarchie (nach TPM-Enrollment)" nennt für Root noch
`1. TPM2 → 2. Passphrase`. Ersetzen durch:

```
  # LUKS-Entsperrung Hierarchie:
  # - Root-Partition:  1. FIDO2 (Nitrokey 3, PIN + Berührung)  2. Passphrase
  #                    KEIN TPM2 mehr — seit 2026-09-12 bewusst entfernt, damit
  #                    ein gestohlener Laptop nicht von allein entsperrt.
  # - Swap-Partition:  1. TPM2 (PCR 0+7+11)  2. Passphrase
  #                    TPM2 bleibt, sonst zweite Berührung beim Aufwachen aus
  #                    dem Ruhezustand.
```

Ebenso den Abschnitt „TPM2-LUKS ENROLLMENT (manueller Schritt, einmalig)": die beiden Zeilen,
die `/dev/nvme0n1p2` beziehungsweise die Root-UUID enrollen, entfernen.

- [ ] **Schritt 4: `docs/TPM-ENROLLMENT.md` nachziehen**

Die Datei hat 129 Zeilen und beschreibt Root durchgehend als TPM2-entsperrt. Konkret zu
ändern:

| Zeile | Heute | Neu |
|---|---|---|
| 14 | „Unlock-Hierarchie nach TPM-Enrollment" | Hierarchie je Gerät trennen: Root = FIDO2 → Passphrase, Swap = TPM2 → Passphrase |
| 33–37 | „### 2. Root-Partition enrollen" mit `--tpm2-pcrs=0+7 /dev/nvme0n1p2` | Abschnitt entfernen, Verweis auf diesen Plan setzen |
| 52–53 | Prüfbefehl `luksDump /dev/nvme0n1p2 \| grep systemd-tpm2` | auf Swap-UUID umstellen |
| 95–98, 110–111 | Re-Enroll- und Wipe-Befehle für `/dev/nvme0n1p2` | entfernen — für Root gibt es kein TPM2-Enrollment mehr |

Nebenbefund beim Nachziehen: Die Datei nennt durchgehend `/dev/nvme0n1p2` und `0+7`, während
die tatsächliche Konfiguration mit UUIDs und `0+7+11` arbeitet. Bei der Gelegenheit
vereinheitlichen.

Oben einen Verweis setzen:

```markdown
> Root wird seit 2026-09-12 **nicht mehr per TPM2** entsperrt, sondern per FIDO2
> (Nitrokey 3, PIN + Berührung) mit Passphrase als Rückfall.
> Siehe `docs/superpowers/specs/2026-09-12-nitrokey-fido2-design.md`.
```

- [ ] **Schritt 5: Bauen**

```nu
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link
```

Nur Kommentare geändert — der Bau muss trotzdem durchlaufen, weil die Kommentare in einem
`script`-String stehen.

- [ ] **Schritt 6: Committen**

```nu
git add modules/secureboot.nix docs/TPM-ENROLLMENT.md
git commit -m "Doku nachgezogen: Root entsperrt per FIDO2, nicht mehr per TPM2"
```

---

## Was dieser Plan nicht tut

Bewusst ausgelassen, jeweils nachrüstbar, sobald die beiden Kernaufgaben belegt laufen:

- **SSH-Schlüssel auf dem Stick** (`id_ed25519_sk`) und Git-Signierung darüber. Die CLAUDE.md
  hält fest, dass die Signierung wegen der Interface-Sperre des Sticks bewusst über
  `~/.ssh/id_ed25519` läuft.
- **WebAuthn im Browser** (Firejail-Profile in `modules/network.nix`, `security.webauthn.*` in
  `home.nix:1453`).
- **OpenPGP/PIV** über die CCID-Schnittstelle.
- **Der Hänger in `tpm2-reenroll`.** Der Dienst blockierte am Swap-Gerät nachweislich drei Tage
  (`journalctl`: 8,6 s Rechenzeit auf 2 d 21 h Laufzeit, 29.08. bis 01.09.), weil
  `systemd-cryptenroll` dort auf eine Passphrase wartet, die im Dienstkontext niemand liefert.
  Nach Aufgabe 7 ist Swap das einzige verbleibende Gerät in dieser Schleife. Gegenmittel wären
  `--unlock-tpm2-device=auto` und ein `TimeoutStartSec`. Eigener Auftrag, eigene Entscheidung.
