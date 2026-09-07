# Personenbezogene Daten aus dem öffentlichen Repo entfernen

**Datum:** 2026-09-07
**Status:** Entwurf zur Abnahme
**Betrifft:** `github.com/achimcc/nixos-config` (öffentlich)

> **Regel für dieses Dokument:** Es wird selbst committet und landet damit in der
> Historie, die wir bereinigen. Es enthält deshalb keinen einzigen Klartextwert.
> Durchgängige Platzhalter: `<USER>` (Systemusername), `<MAIL>` (Mailadresse),
> `<NAME>` (Klarname), `<HOST>` (Hostname).

## 1. Ziel

Systemusername, Mailadresse und Klarname stehen weder im Arbeitsstand noch in der
Git-Historie des öffentlichen Repos im Klartext. Der Hostname ist bereits
generisch (§2.3); von ihm bleiben nur veraltete Doku-Erwähnungen zu tilgen.

## 2. Ausgangslage (gemessen)

| Messung | Wert |
|---|---|
| Commits | 449 |
| Tags | 0 |
| Remote-Branches | nur `origin/main` |
| Commits, die `<MAIL>` einführen oder entfernen | 16 |
| Dateien, die `<MAIL>` je enthielten | 7 |
| Autor-Identitäten in der Historie | 3 (inkl. Variante mit Komma statt Punkt in der TLD) |
| Signierte Commits (Stichprobe 20) | 20 von 20 (`%G?` = `G`) |
| `<USER>`-Vorkommen im Arbeitsstand | 182, davon 54 echte Code-Stellen in 12 Dateien |
| Regex-Treffer auf Mailmuster | 46, davon 13 Fehlalarme |
| Repo-Sichtbarkeit | `PUBLIC` |

Nicht getrackt und damit irrelevant: `.claude/`, `.crush/`.

### 2.1 Die 13 Fehlalarme

Krypto-Algorithmen und GNOME-Extension-UUIDs matchen das Mailmuster, sind aber
keine Personendaten. Sie bleiben unverändert:

- `modules/ssh-hardening.nix:41-53` — `chacha20-poly1305@openssh.com` u. a.
- `modules/home/gnome-settings.nix:67-69` — `appindicatorsupport@rgcjonas.gmail.com` u. a.
- `home-<USER>.nix:119-120` — `caffeine@patapon.info`, `media-controls@cliffniff.github.com`
- `home-<USER>.nix:962` — `curve25519-sha256@libssh.org`
- `modules/power.nix:91` — Kommentar

Ein pauschales `--replace-text` über alle Mailmuster würde diese zerstören. Die
Ersetzung adressiert deshalb ausschließlich die unter §2.2 aufgezählten Werte.

### 2.2 Die vollständige Variantenliste

Aus allen 449 Commits erhoben, nicht nur aus dem Arbeitsstand. Vollständigkeit ist
hier die einzige Eigenschaft, die zählt — eine übersehene Variante macht den
gesamten Rewrite wertlos.

| Variante | Arbeitsstand | Historie | Ersetzung |
|---|---|---|---|
| `<USER>` in drei Schreibweisen (klein, kapitalisiert, Versalien) | 85 | 654 | generischer Username |
| `<USER>.<NACHNAME>` (Mail-Localpart) | 25 | 516 | Platzhalter-Localpart |
| `home-<USER>.nix` | 28 | 847 | `home.nix`, zusätzlich `--path-rename` |
| `<HOST>` = `<USER>-laptop` | 26 | 91 | generischer Hostname |
| `<USER><NACHNAME>` (macOS-Pfad in `PROTONVPN-SETUP.md:59`) | 2 | 2 | Platzhalter |
| `<NAME>` als Klarname | 5 | 471 | Platzhalter |
| `achimcc` (GitHub-Konto) | 2 | 2 | **bleibt unverändert** |

**Der Hostname war in der ersten Fassung dieses Entwurfs nicht erfasst.** Er ist
aus dem Vornamen gebildet und damit genauso personenbezogen wie der Username.

**Reihenfolge und Schutz von `achimcc`:** Eine naive Ersetzung von `<USER>` würde
`achimcc` zu `<neuer-user>cc` verstümmeln und damit jede GitHub-URL im Repo
zerstören — auch die des privaten Identity-Repos. `git filter-repo --replace-text`
verwendet Python-Regex; die Regel für den Username braucht deshalb einen negativen
Lookahead (`regex:<USER>(?!cc)`), und die spezifischen Varianten (Hostname,
Mail-Localpart, Dateiname) müssen als eigene Regeln **vor** der allgemeinen stehen.

### 2.3 Der Hostname — bereits generisch (Korrektur nach Abnahme)

Nachgemessen beim Schreiben des Umsetzungsplans:

```
modules/network.nix:75   hostName = "nixos";
flake.nix:97             nixosConfigurations.nixos
hostnamectl --static  →  nixos
```

**Der Hostname ist bereits `nixos` und damit ohne Personenbezug.** Die
`<USER>-laptop`-Vorkommen sind ausschließlich **veraltete Dokumentation** aus der
Zeit vor der Umbenennung, die `TEST-PLAN.md:12` festhält. `AGENTS.md:36` empfiehlt
noch `--flake …#<USER>-laptop` — ein Aufruf, der heute fehlschlägt, weil es diese
Konfiguration nicht mehr gibt.

Folgen für den Plan:

- **Kein Eingriff ins laufende System.** Das Risiko „Hostname-Änderung stört
  Netzwerkdienste" aus §8 entfällt ersatzlos, ebenso das Risiko
  „Hostname-Mismatch".
- Es bleibt reine Textpflege in `AGENTS.md`, `CLI-TOOLS-CHEATSHEET.md`,
  `PROTONVPN-SETUP.md`, `TEST-PLAN.md`, `restore-vpn.sh`, `configuration.nix:1`
  und dem `.sops.yaml`-Anker `&host_<USER>-laptop`.
- Der `.sops.yaml`-Anker ist ein YAML-Name ohne Funktion für die Entschlüsselung:
  Der Host-Age-Key leitet sich aus dem SSH-Host-Key der Maschine ab, nicht aus
  ihrem Namen. Umbenennen entwertet **keine** Secrets, `sops updatekeys` ist nicht
  nötig.
- Nebenbei wird die Dokumentation dadurch erstmals wieder korrekt.

### 2.4 Nachtrag zur Variantenliste

Beim Erheben der Stellenliste zusätzlich gefunden:

- `flake.nix:2` — `description = "NixOS Konfiguration für <NAME-Vorname>"`

## 3. Zentrale Entscheidung: SOPS ist hier das falsche Werkzeug

Die Aufgabe wurde als „mit SOPS verschlüsseln" gestellt. Die Messung widerlegt das:

**SOPS entschlüsselt zur Laufzeit auf dem Zielsystem, Nix wertet zur Bauzeit aus.**
Ein Wert, der im Nix-Ausdruck selbst steht, muss beim Bauen bekannt sein — SOPS
kann ihn dort nicht ersetzen.

Fast alle betroffenen Stellen sind Bauzeit-Werte:

| Stelle | Art | Werkzeug |
|---|---|---|
| `users.users.<USER>` (`configuration.nix:169`) | Bauzeit → `/etc/passwd` | `identity.nix` |
| `description = "<NAME>"` (`configuration.nix:170`) | Bauzeit | `identity.nix` |
| `home-manager.users.<USER>` (`flake.nix:119`) | Bauzeit, Attributpfad | `identity.nix` |
| `accounts.email.accounts.posteo` (`home-<USER>.nix:397-400`) | Bauzeit → Thunderbird-Profil, mbsync | `identity.nix` |
| `xdg.configFile."goa-1.0/accounts.conf"` (`home-<USER>.nix:427-434`) | Bauzeit → generierte Datei | `identity.nix` |
| `programs.git` `user.name`/`user.email` | Bauzeit → `~/.config/git/config` | `identity.nix` |
| `owner = "<USER>"` (`modules/sops.nix`, 10×) | Bauzeit | `identity.nix` |
| `/home/<USER>/…` (15×) | Bauzeit | `identity.nix` |
| `sudo -u <USER>` (5×) | Bauzeit | `identity.nix` |
| `msmtp` `from`/`user` (`modules/email-alerts.nix:104-105`) | Bauzeit | `identity.nix` |
| `TO=`/`FROM=` im Alert-Script (`modules/email-alerts.nix:29-30`) | Bauzeit (in `writeShellScript` eingebettet) | `identity.nix` |

**Für keine dieser Stellen wird SOPS gebraucht.** Der Ersatz ist ein privates Repo,
kein Verschlüsselungsverfahren. Der bestehende SOPS-Aufbau (`modules/sops.nix`,
`secrets/secrets.yaml`) bleibt unverändert und behält seine Aufgabe: echte
Geheimnisse — Passwörter, Token, private Schlüssel.

Der Kommentar in `modules/email-alerts.nix:29`
(`# Hardcoded, da sops placeholder in script nicht funktioniert`) dokumentiert
genau diesen Irrweg. Er verschwindet mit der Ursache.

**Dass der Wert danach im Nix-Store des Laptops steht, ist kein Mangel.** Der Store
ist lokal; der Username steht ohnehin in `/etc/passwd`. Zu verbergen ist er vor
GitHub, nicht vor dem eigenen Rechner.

## 4. Architektur

```
┌─────────────────────────────────────┐
│ homeserver-secrets  (PRIVAT)        │
│   identity/laptop.nix               │   Klartext, nicht SOPS-verschlüsselt
│     { username, realName, email }   │   (privates Repo braucht keine Chiffre)
└──────────────┬──────────────────────┘
               │ Flake-Input, flake = false
               │ git+ssh://git@github.com/achimcc/homeserver-secrets.git
               ▼
┌─────────────────────────────────────┐
│ nixos-config  (ÖFFENTLICH)          │
│   flake.nix   → id = import "${identity}/identity/laptop.nix"
│   *.nix       → ${id.username}, ${id.email}, ${id.realName}
└─────────────────────────────────────┘
```

`flake = false` bindet ein Repo ohne eigene `flake.nix` ein — `homeserver-secrets`
hat keine. Das Muster ist in `homeserver/flake.nix:89` bereits im Einsatz und
erprobt.

### 4.1 Warum `homeserver-secrets` und kein eigenes Repo

Entschieden zugunsten der Wiederverwendung: ein drittes Repo für drei Werte ist
Overhead, die SSH-Authentifizierung steht, das Repo ist privat und wird ohnehin
gepflegt.

Der Preis, der benannt gehört: Das Repo heißt nach dem Homeserver, enthält künftig
aber Laptop-Daten, und seine `.sops.yaml`-Doku beschreibt es als reines
SOPS-Empfänger-Repo mit getrennten Empfängern für `server` und `vps`. Die
`identity/`-Ablage liegt daneben, nicht darin: sie ist unverschlüsselt und hat
keine Empfänger. Ein Absatz im README des privaten Repos hält das fest.

### 4.2 Der Stolperstein: `sudo nixos-rebuild`

Der Flake-Fetch von `git+ssh://` braucht den SSH-Schlüssel des Nutzers; `root` hat
ihn nicht. Ablauf am Laptop:

1. `nix flake update homeserver-secrets` **als Nutzer** — holt den Input in den Store
2. `sudo nixos-rebuild switch --flake .#<HOST>` — findet ihn dort

Solange der Input gelockt und im Store liegt, funktioniert Schritt 2 ohne Netz.
Nach einem `nix-collect-garbage` kann Schritt 1 nötig werden. Das gehört in die
README des öffentlichen Repos.

## 5. Bausteine

### Baustein A — `identity.nix` im privaten Repo

Datei `identity/laptop.nix` in `homeserver-secrets`:

```nix
{
  username = "…";
  realName = "…";
  email    = "…";
}
```

README-Absatz ergänzen, der erklärt, warum hier unverschlüsselte Daten liegen.

**Der Hostname gehört ausdrücklich nicht hierher.** Er wird stattdessen fest auf
einen generischen Wert gesetzt (Baustein B). Ein Hostname ohne Personenbezug ist
kein Geheimnis und braucht keine Indirektion — das ist die einfachere Lösung, und
sie hält die Zahl der Werte klein, die beim Bauen aus einem fremden Repo kommen
müssen.

### Baustein B — Öffentliches Repo auf `identity` umstellen

54 Code-Stellen in 12 Dateien:

| Datei | Stellen |
|---|---|
| `home-<USER>.nix` → `home.nix` | 17 |
| `modules/sops.nix` | 10 |
| `modules/security.nix` | 6 |
| `modules/network.nix` | 4 |
| `modules/email-alerts.nix` | 4 |
| `modules/logwatch.nix` | 3 |
| `modules/firewall.nix` | 3 |
| `configuration.nix` | 3 |
| `modules/secureboot.nix` | 1 |
| `modules/protonvpn.nix` | 1 |
| `modules/home/gnome-settings.nix` | 1 |
| `flake.nix` | 1 |

Dazu die Kommentare und Dokumentationsdateien (`README.md`,
`CLI-TOOLS-CHEATSHEET.md`, `docs/plans/*`, `docs/TODO-SOPS-EMAIL.md` — letztere
ersatzlos löschen, sie ist erledigt).

Durchreichung: `id` wird über `specialArgs` bzw. `extraSpecialArgs` an alle Module
gegeben, analog zu `inputs`/`pkgs-unstable` in `flake.nix:100` und `flake.nix:118`.

**Veraltete Hostname-Erwähnungen bereinigen** (siehe §2.3): reine Textpflege in
`AGENTS.md`, `CLI-TOOLS-CHEATSHEET.md`, `PROTONVPN-SETUP.md`, `TEST-PLAN.md`,
`restore-vpn.sh`, `configuration.nix:1` und dem `.sops.yaml`-Anker. Der Hostname
selbst ist bereits generisch und wird nicht angefasst.

**Zwei Werte bleiben wertgleich, nur die Herkunft ändert sich:**
- `home-<USER>.nix:420` `thunderbird.profiles = [ "<USER>" ]` — Verzeichnisname unter
  `~/.thunderbird/`; muss denselben Wert behalten, sonst bricht das Profil.
- `home-<USER>.nix:1100` `allowed_signers` — der SSH-Public-Key bleibt, nur der
  Mailkommentar wird interpoliert.

### Baustein C — Historie umschreiben

Werkzeug: `git-filter-repo` 2.47.0, verfügbar per `nix run nixpkgs#git-filter-repo`
(nicht installiert, kein Grund es zu installieren).

1. **Frischer Spiegelklon** — `filter-repo` verlangt ihn und verweigert sonst.
2. `--replace-text` mit einer Regeldatei, die die Varianten aus §2.2 abbildet —
   spezifische Regeln (Hostname, Mail-Localpart, Dateiname, macOS-Pfad) **vor** der
   allgemeinen Username-Regel, und diese mit negativem Lookahead zum Schutz von
   `achimcc`. Nicht per Regex über Mailmuster (siehe §2.1).
3. `--mailmap` für die Autoren- und Committer-Zeilen, alle drei Identitäten
   einschließlich der Komma-Variante.
4. `--path-rename home-<USER>.nix==>home.nix` rückwirkend.
5. Gegenprobe **vor** dem Push, siehe §7.
6. `git push --force`.

### Baustein D — Nacharbeit

- Alle lokalen Checkouts und Worktrees neu klonen; Hashes sind sämtlich neu.
- Signaturen: alle 449 fallen weg. Neu signieren ist ein eigener Schritt und
  ausdrücklich **nicht** Teil dieser Arbeit (449 Signaturvorgänge über den
  SSH-Schlüssel).
- Optional: GitHub Support bitten, die verwaisten Objekte zu sammeln. Ohne das
  bleiben alte Commits per Hash-URL abrufbar. Bewusst akzeptiert.

## 6. Reihenfolge

**A → B → bauen und verifizieren → C → D.**

Zwingend: Baustein C zuletzt. Wird die Historie vor dem Umbau geschrieben, muss sie
danach ein zweites Mal geschrieben werden.

## 7. Verifikation

Kein Schritt gilt als erledigt ohne die Ausgabe seines Kommandos.

| Nach Baustein | Prüfung | Erwartung |
|---|---|---|
| B | `nixos-rebuild build --flake .#<HOST>` | Baut durch |
| B | `id <USER>` nach `switch` | Nutzer unverändert, gleiche UID |
| B | `sudo cat /run/secrets/email/posteo` | SOPS entschlüsselt weiterhin |
| B | `git config user.email` | unveränderter Wert |
| B | `send-security-alert "Test" "Test"` | Mail kommt an |
| B | jede Variante aus §2.2 per `grep -rI` im Arbeitsstand | 0 Treffer, außer `achimcc` |
| C | jede Variante aus §2.2 per `git log --all -S` | 0 Treffer, außer `achimcc` |
| C | `git log --format='%an <%ae>' \| sort -u` | nur die Platzhalter-Identität |
| C | `git ls-files \| grep -i <USER>` | 0 Treffer |
| C | `git grep -i <USER> $(git rev-list --all)` | 0 Treffer, außer `achimcc` |

Zwei Prüfungen tragen das Ergebnis:

**`send-security-alert`** prüft die Kette `identity.nix → msmtp-Konfiguration →
SOPS-Passwort → Posteo` in einem Zug. Ein `exit 0` von `msmtp` allein belegt
nichts — die Mail muss ankommen.

**`sudo cat /run/secrets/email/posteo`** belegt, dass die Hostname-Änderung den
SOPS-Host-Key nicht entwertet hat (§2.3). Diese Prüfung läuft **vor** dem
`send-security-alert`; schlägt sie fehl, ist die Ursache dort und nicht bei msmtp.

Die Variantenprüfung erfolgt über die vollständige Liste aus §2.2, nicht über eine
Auswahl. Sie ist die einzige Prüfung, die Baustein C überhaupt validiert.

## 8. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Force-push kollidiert mit parallelen Sessions | Vor Baustein C alle anderen Sessions und Worktrees abschließen. Das ist eine Absprache, kein technischer Schritt. |
| Home-Manager-Aktivierung bricht durch Attributpfad-Änderung | Baustein B zuerst mit `nixos-rebuild build`, erst dann `switch` |
| Thunderbird-Profil wird nicht mehr gefunden | Wert bleibt gleich (§ Baustein B) |
| `git+ssh`-Input beim Rebuild nicht auflösbar | Ablauf in §4.2, dokumentiert in der README |
| GNOME-Keyring nimmt Schaden | Baustein B fasst weder Keyring-Dateien noch die Guard-/Backup-Dienste an; deren `owner`-Angaben ändern nur ihre Herkunft, nicht ihren Wert |
| Ersetzung zerstört GitHub-URLs | `achimcc` per negativem Lookahead schützen (§2.2); nach dem Rewrite `git grep achimcc` gegenprüfen |
| Eine Variante wird übersehen | Prüfung gegen die vollständige Liste aus §2.2, erhoben aus allen 449 Commits — nicht gegen den Arbeitsstand. Die erste Fassung dieses Entwurfs hatte den Hostnamen übersehen; das ist der Beleg, dass die Stichprobe nicht reicht |

## 9. Ausdrücklich nicht Teil dieser Arbeit

- Der GitHub-Kontoname in URL, Profil und Contribution-Graph. Nicht entfernbar,
  solange das Repo dort liegt.
- Die Verknüpfbarkeit über den SSH-Public-Key, der unter `github.com/<konto>.keys`
  öffentlich abrufbar ist.
- Neusignierung der umgeschriebenen Commits.
- Das private `homeserver`-Repo. Es enthält dieselben Daten, ist aber privat.
