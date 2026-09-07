# Personenbezogene Daten aus dem öffentlichen Repo entfernen — Umsetzungsplan

> **Für agentische Ausführung:** ERFORDERLICHE SUB-SKILL:
> `superpowers:subagent-driven-development` (empfohlen) oder
> `superpowers:executing-plans`. Schritte tragen Checkbox-Syntax (`- [ ]`).

**Ziel:** Systemusername, Mailadresse und Klarname stehen weder im Arbeitsstand
noch in der Historie des öffentlichen Repos `nixos-config`.

**Architektur:** Die Werte wandern in eine `identity/laptop.nix` im privaten Repo
`homeserver-secrets`, das per `flake = false` als Flake-Input eingebunden wird.
Alle 54 Code-Stellen referenzieren danach `${id.username}`, `${id.email}` bzw.
`${id.realName}`. Zuletzt wird die Historie mit `git filter-repo` umgeschrieben.
SOPS wird dafür **nicht** verwendet und bleibt unverändert — die Begründung steht
in §3 der Spec.

**Tech-Stack:** Nix Flakes, Home Manager, `git-filter-repo` 2.47.0
(`nix run nixpkgs#git-filter-repo`, nicht installiert).

**Spec:** `docs/superpowers/specs/2026-09-07-pii-aus-oeffentlichem-repo-entfernen-design.md`

---

## Globale Rahmenbedingungen

- **Dieses Dokument und jede Commit-Nachricht enthalten keinen Klartextwert.** Sie
  gehen in die Historie ein, die bereinigt wird. Platzhalter durchgängig:
  `<USER>`, `<MAIL>`, `<NAME>`, `<NACHNAME>`.
- **Die Prüfkommandos verwenden `$U` statt des Usernamens.** Einmal pro Shell
  setzen — der gesuchte Name ist der des laufenden Nutzers, es braucht also
  keine Eingabe:

  ```bash
  U=$(id -un)
  echo "Suchbegriff gesetzt: ${#U} Zeichen"
  ```

  Nach einem `cd` in eine neue Shell erneut setzen. Ein leeres `$U` lässt jedes
  `grep` alles finden — der Umfang der Treffer ist deshalb immer gegen die im
  jeweiligen Schritt genannte Erwartung zu halten.
- **Der Zielwert für den Username lautet `user`**, für die Mail-Domain bleibt
  `posteo.de` erhalten (kein Personenbezug), der Localpart wird `user`. Der
  Klarname wird zu `NixOS User`.
- **`achimcc` bleibt unverändert.** Es ist der GitHub-Kontoname und steht in jeder
  Repo-URL. Jede Ersetzungsregel für den Username braucht den negativen Lookahead
  `(?!cc)`, sonst zerbrechen die URLs — auch die des privaten Identity-Repos.
- **Flakes sehen nur git-getrackte Dateien.** Nach jeder neuen Datei erst
  `git add`, sonst meldet `nixos-rebuild` sie als nicht existent. Das gilt auch
  für unversionierte Änderungen an bestehenden Dateien nicht — die sieht Nix.
- **Arbeitsverzeichnis:** der Worktree `.claude/worktrees/sops-pii`, Branch
  `worktree-sops-pii`. Andere Sessions arbeiten parallel im Hauptcheckout.
- **`nix build … | tail` gibt tails Exit-Code zurück** — bei Pipes
  `${PIPESTATUS[0]}` prüfen (CLAUDE.md).
- **Kein Schritt gilt als erledigt ohne die Ausgabe seines Kommandos.** `exit 0`
  belegt nichts.
- **Der Push in Task 8 ist unumkehrbar.** Er wird erst nach ausdrücklicher
  Freigabe ausgeführt.

---

### Task 0: Ersetzungsdatei sichern, solange die Werte noch da sind

Diese Task muss **zuerst** laufen. Nach Task 2–5 stehen die echten Werte nicht mehr
im Arbeitsstand — die Regeldatei für Task 7 wäre dann nicht mehr aus dem Repo
ableitbar.

**Dateien:**
- Anlegen (**nicht** versioniert):
  `~/pii-rewrite/replacements.txt`

- [ ] **Schritt 1: Regeldatei schreiben**

Die Datei enthält Klartextwerte und darf **niemals** ins Repo. Format von
`git filter-repo --replace-text`: eine Regel pro Zeile, `alt==>neu`, wahlweise mit
Präfix `literal:` oder `regex:`. Die Reihenfolge ist bedeutsam — spezifische
Regeln zuerst, die allgemeine Username-Regel zuletzt.

```
literal:<MAIL-mit-Punkt-TLD>==>user@posteo.de
literal:<MAIL-mit-Komma-TLD>==>user@posteo.de
literal:<NAME>==>NixOS User
literal:<USER><NACHNAME>==>user
literal:<USER>.<NACHNAME>==>user
literal:home-<USER>.nix==>home.nix
literal:<USER>-laptop==>nixos
regex:(?i)<USER>(?!cc)==>user
```

Die letzte Regel ist case-insensitive (`(?i)`) und fängt damit die
kapitalisierte und die Versalien-Schreibweise aus §2.2 der Spec mit ab.

- [ ] **Schritt 2: Prüfen, dass die Regeln greifen — und `achimcc` verschonen**

```bash
python3 - "$U" <<'EOF'
import re, sys
u = sys.argv[1]
for probe in [u + "cc", u, u.capitalize(), u.upper(), u + "-laptop"]:
    print(f"{probe:16} -> {re.sub(rf'(?i){u}(?!cc)', 'user', probe)}")
EOF
```

Erwartet — der GitHub-Kontoname bleibt unangetastet, alle drei Schreibweisen des
Usernamens werden ersetzt:

```
<USER>cc         -> <USER>cc        ← unverändert, das ist der Punkt
<USER>           -> user
<User>           -> user
<USER-VERSALIEN> -> user
<USER>-laptop    -> user-laptop
```

Die letzte Zeile zeigt nur, was die allgemeine Regel für sich genommen täte. In
der echten Regeldatei greift die vorgelagerte Literal-Regel für
`<USER>-laptop` vorher und setzt `nixos` ein.

- [ ] **Schritt 3: Sicherstellen, dass die Datei nicht versioniert ist**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git status --short
```

Erwartet: kein Eintrag für `replacements.txt` (sie liegt außerhalb des Repos).

---

### Task 1: `identity.nix` anlegen und als Flake-Input einbinden

Diese Task ändert **keinen einzigen** der 54 Vorkommen. Ihr Ergebnis ist allein:
`id` ist in allen Modulen verfügbar und das System baut unverändert durch. Damit
ist die Infrastruktur getrennt von der inhaltlichen Umstellung überprüfbar.

**Dateien:**
- Anlegen: `identity/laptop.nix` im Repo `homeserver-secrets` (privat)
- Ändern: `flake.nix:3-46` (Inputs), `flake.nix:48` (outputs-Kopf),
  `flake.nix:100` (`specialArgs`), `flake.nix:118` (`extraSpecialArgs`)

**Schnittstellen:**
- Erzeugt: das Attributset `id` mit den Feldern `username` (String),
  `realName` (String), `email` (String). Alle folgenden Tasks nutzen genau diese
  drei Namen.

- [ ] **Schritt 1: `identity/laptop.nix` im privaten Repo anlegen**

```bash
mkdir -p ~/Projects/homeserver-secrets/identity
```

Inhalt von `~/Projects/homeserver-secrets/identity/laptop.nix` — die
drei echten Werte eintragen, wie sie heute in `configuration.nix:169-171` und
`home-<USER>.nix:399-401` stehen:

```nix
# Identität des Laptops. Klartext und mit Absicht nicht SOPS-verschlüsselt:
# Dieses Repo ist privat, und die Werte werden zur BAUZEIT gebraucht — sops-nix
# entschlüsselt erst zur Laufzeit auf dem Ziel und käme dafür zu spät.
# Siehe nixos-config, docs/superpowers/specs/2026-09-07-…-design.md §3.
{
  username = "…";   # Systemusername, entspricht users.users.<name>
  realName = "…";   # Klarname für git und users.users.<name>.description
  email    = "…";   # Mailadresse für git, msmtp, mbsync, GOA
}
```

- [ ] **Schritt 2: README des privaten Repos ergänzen**

Anhängen an `~/Projects/homeserver-secrets/README.md`:

```markdown
## `identity/` — unverschlüsselt, mit Absicht

Neben den SOPS-Secrets liegt hier `identity/laptop.nix`: Username, Klarname und
Mailadresse des Laptops im Klartext.

Warum nicht verschlüsselt: Diese Werte werden zur **Bauzeit** von Nix gebraucht.
sops-nix entschlüsselt erst zur **Laufzeit** auf dem Zielsystem und kommt dafür zu
spät. Der Schutz besteht darin, dass dieses Repo privat ist — nicht darin, dass
die Datei chiffriert wäre.

Verbraucher: `nixos-config` (öffentlich) bindet dieses Repo als Flake-Input mit
`flake = false` ein.
```

- [ ] **Schritt 3: Im privaten Repo committen und pushen**

Der Flake-Input zieht über `git+ssh` vom Remote — eine nur lokal committete Datei
findet er nicht.

```bash
cd ~/Projects/homeserver-secrets
git add identity/laptop.nix README.md
git commit -m "identity: Laptop-Identität für nixos-config bereitstellen"
git push
```

- [ ] **Schritt 4: Input in `flake.nix` eintragen**

Nach dem `rcu`-Input (`flake.nix:45`) einfügen:

```nix
    # Identität des Laptops (Username, Klarname, Mailadresse) aus dem PRIVATEN
    # Repo. Diese Werte werden zur Bauzeit gebraucht; SOPS scheidet dafür aus,
    # weil es erst zur Laufzeit auf dem Ziel entschlüsselt.
    # `flake = false`, weil das Repo keine eigene flake.nix hat.
    #
    # Preis, den man kennen muss: `sudo nixos-rebuild` kann diesen Input nicht
    # selbst holen — root hat den SSH-Schlüssel nicht. Nach einem
    # `nix-collect-garbage` deshalb erst als Nutzer:
    #   nix flake update identity
    # und danach der übliche Rebuild.
    identity = {
      url = "git+ssh://git@github.com/achimcc/homeserver-secrets.git";
      flake = false;
    };
```

- [ ] **Schritt 5: `id` im `let`-Block bereitstellen und durchreichen**

`flake.nix:48` — `identity` in den outputs-Kopf aufnehmen:

```nix
  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llm-agents, sops-nix, lanzaboote, nix-flatpak, rcu, identity, ... } @inputs:
```

Im `let`-Block nach `system = "x86_64-linux";` ergänzen:

```nix
      # Identität aus dem privaten Repo. Ein Attributset { username, realName, email }.
      id = import "${identity}/identity/laptop.nix";
```

`flake.nix:100` erweitern:

```nix
        specialArgs = { inherit inputs llm-agents pkgs-unstable id; };
```

`flake.nix:118` erweitern:

```nix
            home-manager.extraSpecialArgs = { inherit llm-agents pkgs-unstable rcu id; };
```

- [ ] **Schritt 6: Input holen und Lockfile schreiben**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nix flake lock
```

Erwartet: `flake.lock` enthält einen Eintrag `identity`. Prüfen mit:

```bash
grep -A3 '"identity"' flake.lock
```

- [ ] **Schritt 7: Bauen — muss unverändert durchlaufen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nixos-rebuild build --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`. Es wurde noch nichts inhaltlich geändert; ein Fehler hier
liegt am Input oder am Durchreichen, nicht an der Konfiguration.

- [ ] **Schritt 8: Gegenprobe, dass `id` wirklich ankommt**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nix eval --no-eval-cache --raw .#nixosConfigurations.nixos._module.specialArgs.id.username
```

Erwartet: der echte Username. Schlägt das mit `path '<hash>.drv' is not valid`
fehl, ist ein Eval-Cache nach `nix-collect-garbage` verwaist — `--no-eval-cache`
ist bereits gesetzt und erzeugt ihn neu (CLAUDE.md).

- [ ] **Schritt 9: Commit**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git add flake.nix flake.lock
git commit -m "flake: Identität aus privatem Repo als Input einbinden

Bereitet die Ablösung der hartkodierten Personendaten vor. Ändert noch
keinen Verwendungsort — id ist ab jetzt lediglich in allen Modulen
verfügbar."
```

---

### Task 2: `configuration.nix` und `flake.nix` umstellen

**Dateien:**
- Ändern: `configuration.nix:1`, `:169`, `:171`, `:365`, `:369`
- Ändern: `flake.nix:2`, `flake.nix:119`

**Schnittstellen:**
- Verbraucht: `id.username`, `id.realName` aus Task 1

- [ ] **Schritt 1: Prüfung vorher — die Treffer sichtbar machen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -ni "$U" -- configuration.nix flake.nix
```

Erwartet: 6 Treffer (`configuration.nix` 4, `flake.nix` 2). Diese Zahl ist das
Abnahmekriterium für Schritt 5.

- [ ] **Schritt 2: Modulkopf von `configuration.nix` erweitern**

Zeile 1 des Attributsets — aus:

```nix
{ config, pkgs, lib, ... }:
```

wird:

```nix
{ config, pkgs, lib, id, ... }:
```

- [ ] **Schritt 3: `configuration.nix` umstellen**

Zeile 1 (Kommentar): `# NixOS Hauptkonfiguration für <USER>-laptop`
→ `# NixOS Hauptkonfiguration für den Laptop (Host: nixos)`

Zeilen 169-174 — aus:

```nix
  users.users.<USER> = {
    isNormalUser = true;
    description = "<NAME>";
    extraGroups = [ "networkmanager" "wheel" "input" ];
    shell = pkgs.nushell;
  };
```

wird:

```nix
  users.users.${id.username} = {
    isNormalUser = true;
    description = id.realName;
    extraGroups = [ "networkmanager" "wheel" "input" ];
    shell = pkgs.nushell;
  };
```

Zeile 365 — aus `User = "<USER>";` wird `User = id.username;`

Zeile 369 — aus `cd ~/nixos-config` wird
`cd /home/${id.username}/nixos-config`

- [ ] **Schritt 4: `flake.nix` umstellen**

Zeile 2 — aus:

```nix
  description = "NixOS Konfiguration für user";
```

wird:

```nix
  description = "NixOS Konfiguration für einen ThinkPad T14 Gen 5";
```

Zeile 119 — aus:

```nix
            home-manager.users.<USER> = import ./home-<USER>.nix;
```

wird:

```nix
            home-manager.users.${id.username} = import ./home-<USER>.nix;
```

Die Datei wird erst in Task 4 umbenannt; hier bleibt der Pfad wie er ist.

- [ ] **Schritt 5: Prüfung nachher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -ni "$U" -- configuration.nix flake.nix
echo "Treffer: $?"
```

Erwartet: keine Ausgabe, `Treffer: 1` (grep findet nichts).

- [ ] **Schritt 6: Bauen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nixos-rebuild build --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`.

- [ ] **Schritt 7: Gegenprobe, dass der Nutzer unverändert bleibt**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nix eval --no-eval-cache .#nixosConfigurations.nixos.config.users.users."$(id -un)".description
```

Erwartet: der Klarname. Ein leeres Ergebnis oder ein Fehler bedeutet, dass der
Attributpfad nicht mehr auf denselben Nutzer zeigt — dann stimmt `id.username`
nicht mit dem laufenden Nutzer überein.

- [ ] **Schritt 8: Commit**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git add configuration.nix flake.nix
git commit -m "config: Nutzer und Klarname aus der Identität beziehen"
```

---

### Task 3: System-Module umstellen

**Dateien:**
- Ändern: `modules/sops.nix` (10 Stellen), `modules/security.nix` (5),
  `modules/network.nix` (4), `modules/email-alerts.nix` (4),
  `modules/logwatch.nix` (3), `modules/firewall.nix` (3),
  `modules/secureboot.nix` (1), `modules/protonvpn.nix` (1)

**Schnittstellen:**
- Verbraucht: `id.username`, `id.email` aus Task 1

- [ ] **Schritt 1: Prüfung vorher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rni "$U" -- modules/sops.nix modules/security.nix modules/network.nix modules/email-alerts.nix modules/logwatch.nix modules/firewall.nix modules/secureboot.nix modules/protonvpn.nix | grep -c .
```

Erwartet: `35` (31 Code-Stellen plus 4 Kommentarzeilen).

- [ ] **Schritt 2: Modulköpfe erweitern**

In allen acht Dateien `id` in den Kopf aufnehmen, z. B. `modules/sops.nix`:

```nix
{ config, lib, pkgs, id, ... }:
```

Bei `modules/network.nix` lautet der Kopf
`{ config, lib, pkgs, pkgs-unstable, id, ... }:`.

- [ ] **Schritt 3: `modules/sops.nix` umstellen**

Alle zehn Vorkommen. Die acht `owner`-Zeilen (39, 45, 51, 60, 65, 72, 76, 80) —
aus `owner = "<USER>";` wird `owner = id.username;`

Zeile 62: `path = "/home/<USER>/.ssh/hetzner-vps";`
→ `path = "/home/${id.username}/.ssh/hetzner-vps";`

Zeile 67: `path = "/home/<USER>/.ssh/hetzner-vps.pub";`
→ `path = "/home/${id.username}/.ssh/hetzner-vps.pub";`

Achtung: Die `path`-Werte stehen in einem Nix-String, die `owner`-Werte nicht.
`owner = "${id.username}";` wäre funktionsgleich, aber überflüssig verklausuliert.

- [ ] **Schritt 4: `modules/security.nix` umstellen**

Die AIDE-Regeln in den Zeilen 431, 448-452 stehen in einem mehrzeiligen
Nix-String (`''…''`), Interpolation greift dort:

```
    /home/${id.username}/nixos-config CONTENT
    …
    !/home/${id.username}/nixos-config/.git
    !/home/${id.username}/nixos-config/.claude
    !/home/${id.username}/nixos-config/.crush
    !/home/${id.username}/nixos-config/flake.lock
    !/home/${id.username}/nixos-config/result
```

- [ ] **Schritt 5: `modules/network.nix` umstellen**

Zeilen 567, 577: `"--private=/home/<USER>/Downloads"`
→ `"--private=/home/${id.username}/Downloads"`

Zeile 635: `"--whitelist=/home/<USER>/Dokumente/Logseq"`
→ `"--whitelist=/home/${id.username}/Dokumente/Logseq"`

Zeile 673: `"--whitelist=/home/<USER>/Downloads"`
→ `"--whitelist=/home/${id.username}/Downloads"`

- [ ] **Schritt 6: `modules/email-alerts.nix` umstellen**

Zeilen 25-26 stehen im `writeShellScript`-Rumpf. Der irreführende Kommentar
verschwindet mit der Ursache:

```bash
    TO="${id.email}"
    FROM="${id.email}"
```

Zeilen 64-65 in der msmtp-Konfiguration:

```nix
        from = id.email;
        user = id.email;
```

- [ ] **Schritt 7: `modules/logwatch.nix` umstellen**

Zeile 112: `--user <USER>` → `--user ${id.username}`
Zeile 293: `sudo -u <USER>` → `sudo -u ${id.username}`
Zeile 374: `sudo faillock --user <USER> --reset` →
`sudo faillock --user ${id.username} --reset`

- [ ] **Schritt 8: `modules/firewall.nix` umstellen**

Zeile 512: `CACHE="/home/<USER>/.cache/Proton/VPN/serverlist.json"`
→ `CACHE="/home/${id.username}/.cache/Proton/VPN/serverlist.json"`

Zeile 519: `if [ "$CACHE_OWNER" != "<USER>" ]; then`
→ `if [ "$CACHE_OWNER" != "${id.username}" ]; then`

Zeile 520: `(erwartet: <USER>)` → `(erwartet: ${id.username})`

- [ ] **Schritt 9: `modules/secureboot.nix` und `modules/protonvpn.nix` umstellen**

`modules/secureboot.nix:52` und `modules/protonvpn.nix:58`: jeweils
`sudo -u <USER>` → `sudo -u ${id.username}`

- [ ] **Schritt 10: Prüfung nachher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rni "$U" -- modules/*.nix
```

Erwartet: keine Ausgabe.

- [ ] **Schritt 11: Bauen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nixos-rebuild build --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`. Ein Fehler `undefined variable 'id'` bedeutet einen
vergessenen Modulkopf aus Schritt 2.

- [ ] **Schritt 12: Gegenprobe an der gebauten msmtp-Konfiguration**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nix eval --no-eval-cache --raw .#nixosConfigurations.nixos.config.programs.msmtp.accounts.default.from
```

Erwartet: die echte Mailadresse. Das belegt, dass die Interpolation greift und
nicht etwa ein leerer String eingesetzt wurde.

- [ ] **Schritt 13: Commit**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git add modules/
git commit -m "module: Nutzername und Mailadresse aus der Identität beziehen

Loest nebenbei den Workaround in email-alerts.nix ab: der Kommentar
'sops placeholder in script nicht funktioniert' beschrieb einen Irrweg
— die Werte sind Bauzeit-Werte und gehoeren nicht in SOPS."
```

---

### Task 4: `home-<USER>.nix` umstellen und umbenennen

**Dateien:**
- Ändern und umbenennen: `home-<USER>.nix` → `home.nix` (19 Stellen)
- Ändern: `flake.nix:119` (Importpfad)
- Ändern: `modules/home/gnome-settings.nix:143`

**Schnittstellen:**
- Verbraucht: `id.username`, `id.realName`, `id.email` aus Task 1

- [ ] **Schritt 1: Prüfung vorher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -nic "$U" -- home-<USER>.nix
```

Erwartet: `28`.

- [ ] **Schritt 2: Modulköpfe erweitern**

`home-<USER>.nix` Zeile 1:

```nix
{ config, pkgs, pkgs-unstable, llm-agents, rcu, lib, id, ... }:
```

`modules/home/gnome-settings.nix` Zeile 1:

```nix
{ config, lib, pkgs, id, ... }:
```

- [ ] **Schritt 3: Mailkonto umstellen (Zeilen 399-401, 420)**

```nix
    address = id.email;
    userName = id.email;
    realName = id.realName;
```

Zeile 420 — der Wert bleibt derselbe, nur die Herkunft ändert sich. Der
Thunderbird-Profilname ist ein Verzeichnisname unter `~/.thunderbird/`; ein
anderer Wert würde das Profil unauffindbar machen:

```nix
      profiles = [ id.username ];
```

- [ ] **Schritt 4: GOA-Kalender umstellen (Zeilen 429-433)**

Der Block steht in einem `''…''`-String, Interpolation greift:

```
    Identity=${id.email}
    PresentationIdentity=${id.email}
    Uri=https://posteo.de:8443
    CalendarEnabled=true
    CalDavUri=https://posteo.de:8443/calendars/${id.email}/default/
```

- [ ] **Schritt 5: Keyring- und mbsync-Stellen umstellen (Zeilen 810, 831, 838, 918)**

Zeile 810:

```bash
        EXISTING=$(${pkgs.libsecret}/bin/secret-tool lookup protocol imap server posteo.de user "${id.email}" 2>/dev/null || echo "")
```

Zeilen 831 und 838: `user "<MAIL>"` → `user "${id.email}"`

Zeile 918:

```bash
        ${pkgs.gnupg}/bin/gpg --armor --export ${id.email} \
```

- [ ] **Schritt 6: Restliche Pfade und Git-Identität umstellen**

Zeile 949:
`"/home/<USER>/.config/thunderbird-gpg/gpg-wrapper.sh"`
→ `"/home/${id.username}/.config/thunderbird-gpg/gpg-wrapper.sh"`

Zeilen 1038-1039:

```nix
      user.name = id.realName;
      user.email = id.email;
```

Zeile 1062 — der SSH-Public-Key selbst bleibt unverändert, nur die beiden
Mailadressen ringsum werden interpoliert:

```
    ${id.email} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBEnBXC5ijeHaellXY2+SOUPN/JnmKuRfHDK1YGB2Mo ${id.email}
```

Zeilen 1206, 1219: `/home/<USER>/.local/bin/codium`
→ `/home/${id.username}/.local/bin/codium`

Zeile 1486 (Bubblewrap-PATH):
`"/run/wrappers/bin:/home/<USER>/.local/bin:…"`
→ `"/run/wrappers/bin:/home/${id.username}/.local/bin:…"`

Zeile 1670:
`nrs = "sudo nixos-rebuild switch --flake ~/nixos-config#nixos";`
→ `nrs = "sudo nixos-rebuild switch --flake /home/${id.username}/nixos-config#nixos";`

- [ ] **Schritt 7: `modules/home/gnome-settings.nix:143` umstellen**

```nix
      command = "/home/${id.username}/.local/bin/totp-posteo";
```

- [ ] **Schritt 8: Kommentare bereinigen**

Verbleibende Erwähnungen in Kommentaren tilgen — die Dateireferenzen
`home-<USER>.nix` werden in Schritt 9 ohnehin falsch:

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rn "home-$U" -- *.nix modules/
```

Jeden Treffer auf `home.nix` ändern. Betroffen sind unter anderem
`home-<USER>.nix:1178`, `modules/network.nix:505`, `:581`, `:681`, `:683`,
`modules/home/neovim.nix:16`.

- [ ] **Schritt 9: Datei umbenennen und Import anpassen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git mv home-<USER>.nix home.nix
```

`flake.nix:119` anpassen:

```nix
            home-manager.users.${id.username} = import ./home.nix;
```

- [ ] **Schritt 10: Prüfung nachher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rni "$U" -- *.nix modules/
git ls-files | grep -i "$U"
```

Erwartet: beide Kommandos ohne Ausgabe.

- [ ] **Schritt 11: Bauen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nixos-rebuild build --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`.

- [ ] **Schritt 12: Gegenprobe an der gebauten Git-Konfiguration**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nix eval --no-eval-cache --raw .#nixosConfigurations.nixos.config.home-manager.users."$(id -un)".programs.git.userEmail
```

Erwartet: die echte Mailadresse.

- [ ] **Schritt 13: Commit**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git add -A
git commit -m "home: Identität beziehen und Datei zu home.nix umbenennen

Der Dateiname trug den Nutzernamen und muesste sonst in Task 7 ueber
--path-rename nachgezogen werden."
```

---

### Task 5: Dokumentation bereinigen

**Dateien:**
- Ändern: `README.md`, `AGENTS.md`, `CLI-TOOLS-CHEATSHEET.md`,
  `PROTONVPN-SETUP.md`, `TEST-PLAN.md`, `restore-vpn.sh`, `.sops.yaml`,
  `docs/MIGRATION-IPTABLES-TO-NFTABLES.md`,
  `docs/plans/2026-02-05-migrate-iptables-to-nftables.md`,
  `docs/plans/2026-02-03-gpg-nitrokey-thunderbird-design.md`
- Löschen: `docs/TODO-SOPS-EMAIL.md`

- [ ] **Schritt 1: Prüfung vorher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rlni "$U" -- . --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.crush
```

Erwartet: die oben genannten Dateien plus
`docs/superpowers/specs/`- und `docs/superpowers/plans/`-Dateien, in denen nur
`achimcc` steht.

- [ ] **Schritt 2: Erledigte TODO-Datei löschen**

`docs/TODO-SOPS-EMAIL.md` fordert, die Adresse in SOPS einzutragen. Genau das ist
nach §3 der Spec der falsche Weg — die Datei ist gegenstandslos:

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
git rm docs/TODO-SOPS-EMAIL.md
```

- [ ] **Schritt 3: Veraltete Hostnamen korrigieren**

`AGENTS.md:36`, `:42`, `:48`, `:198`, `:201`, `:204`,
`CLI-TOOLS-CHEATSHEET.md:85`, `:983`, `restore-vpn.sh:26`,
`PROTONVPN-SETUP.md:59` nennen `--flake …#<USER>-laptop`. Diese Konfiguration
existiert seit der Umbenennung nicht mehr (`TEST-PLAN.md:12`); die Aufrufe sind
heute schlicht falsch. Korrekt ist durchgängig:

```bash
sudo nixos-rebuild switch --flake /home/<username>/nixos-config#nixos
```

Beschreibende Erwähnungen (`AGENTS.md:5`, `CLI-TOOLS-CHEATSHEET.md:3`, `:1373`,
`configuration.nix:1`) auf „den Laptop (Host `nixos`)" umformulieren.

- [ ] **Schritt 4: `.sops.yaml`-Anker umbenennen**

Zeilen 6, 9 und 17 — der Anker ist ein YAML-Name ohne Funktion für die
Entschlüsselung (Spec §2.3):

```yaml
  # Benutzer Keys (für lokales Editieren)
  - &user_laptop age1ysu70tzmjnh464ruh0jsf7g207hj3ufkqwn7ap0zet69vjy0wv9q7p077h

  # Host Keys (werden beim ersten Boot generiert)
  - &host_laptop age1g50dwjpmlc9404w3f3rgjmamws6zf9g3vlgyylgj3rygfedasprsj4lqzv
```

und in den `creation_rules` entsprechend `*user_laptop` / `*host_laptop`.

- [ ] **Schritt 5: `PROTONVPN-SETUP.md:59` — den macOS-Pfad tilgen**

Die Zeile nennt einen Pfad `/Users/<vorname><nachname>/…`, der auf diesem System
nie existiert hat. Ersetzen durch:

```bash
sudo nixos-rebuild switch --flake /home/<username>/nixos-config#nixos
```

- [ ] **Schritt 6: Restliche Erwähnungen in `README.md` und `docs/`**

`README.md:973-974` nennt Mailadresse und Signing-Key-Identität. Beide streichen
oder auf „siehe privates Identity-Repo" verweisen. In den `docs/plans/`-Dateien
die Mailadresse durch `<mail>` ersetzen — es sind abgeschlossene Planungsdokumente,
ihre Aussage bleibt ohne den konkreten Wert erhalten.

- [ ] **Schritt 7: Prüfung nachher**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
grep -rni -P "$U(?!cc)" -- . --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.crush
```

Erwartet: keine Ausgabe. Die `-P`-Option ist nötig, weil `(?!cc)` ein
Perl-Lookahead ist; ohne sie meldet grep einen Syntaxfehler.

- [ ] **Schritt 8: Bauen und committen**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
nixos-rebuild build --flake .#nixos
echo "Exit: $?"
git add -A
git commit -m "docs: Personendaten entfernen und veraltete Hostnamen korrigieren

Die Rebuild-Aufrufe nannten durchweg '#<USER>-laptop' — eine
Konfiguration, die es seit der Umbenennung auf '#nixos' nicht mehr gibt.
Die Doku war an dieser Stelle nicht nur personenbezogen, sondern falsch."
```

---

### Task 6: Das System tatsächlich schalten und die Kette prüfen

Bis hierher wurde nur gebaut. Diese Task schaltet um und prüft, dass nichts
zerbrochen ist — **vor** dem unumkehrbaren History-Rewrite.

- [ ] **Schritt 1: Umschalten**

```bash
cd ~/nixos-config/.claude/worktrees/sops-pii
sudo nixos-rebuild switch --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`. Bei
`error: cannot fetch input 'git+ssh://…'` greift §4.2 der Spec: erst
`nix flake update identity` als Nutzer, dann erneut.

- [ ] **Schritt 2: Nutzer unverändert**

```bash
id -un && id -u
```

Erwartet: derselbe Name und dieselbe UID wie vorher (1000). Eine geänderte UID
wäre ein schwerer Fehler — dann zeigt `id.username` nicht auf den bestehenden
Nutzer.

- [ ] **Schritt 3: SOPS entschlüsselt weiterhin**

```bash
sudo test -s /run/secrets/email/posteo && echo "Secret vorhanden und nicht leer"
```

Erwartet: die Meldung. Diese Prüfung läuft **vor** Schritt 5; schlägt sie fehl,
liegt die Ursache bei SOPS und nicht bei msmtp.

- [ ] **Schritt 4: Git-Identität unverändert**

```bash
git config user.email && git config user.name
```

Erwartet: die echten Werte, unverändert gegenüber vorher.

- [ ] **Schritt 5: Die Mailkette durchmessen**

```bash
send-security-alert "Test nach Identitaets-Umstellung" "Wenn diese Mail ankommt, funktioniert die Kette identity.nix -> msmtp -> SOPS-Passwort -> Posteo."
echo "Exit: $?"
```

Erwartet: `Exit: 0` **und** die Mail im Posteo-Postfach. Der Exit-Code allein
belegt nichts — msmtp beendet sich auch dann erfolgreich, wenn der Server die
Nachricht später verwirft. Bei Zweifeln:

```bash
sudo tail -20 /var/log/msmtp.log
```

- [ ] **Schritt 6: Thunderbird-Profil noch auffindbar**

```bash
ls -d ~/.thunderbird/*/ 2>/dev/null | head
```

Erwartet: das bestehende Profilverzeichnis, unverändert.

---

### Task 7: Historie umschreiben

**Voraussetzung:** Tasks 1-6 abgeschlossen, System läuft, Mailtest bestanden.

**Dateien:** keine im Arbeitsverzeichnis — gearbeitet wird auf einem Spiegelklon
im Scratchpad.

- [ ] **Schritt 1: Alle parallelen Sessions abschließen**

Dieser Schritt ist eine Absprache, kein Kommando. Der Rewrite ändert **alle** 449
Commit-Hashes; jeder andere Checkout und Worktree wird danach unbrauchbar. Vor dem
Weitermachen bestätigen lassen, dass keine andere Session mehr am Repo arbeitet.

```bash
cd ~/nixos-config
git worktree list
git status --short
```

Nicht committete Änderungen im Hauptcheckout gehen beim Neuklonen verloren — sie
müssen vorher gesichert oder committet sein.

- [ ] **Schritt 2: Branch in den Hauptbranch übernehmen**

```bash
cd ~/nixos-config
git checkout main
git merge --no-ff worktree-sops-pii -m "Identität aus dem oeffentlichen Repo loesen"
git log --oneline -1
```

- [ ] **Schritt 3: Spiegelklon anlegen**

`filter-repo` verweigert die Arbeit auf einem Klon mit Fremdzuständen:

```bash
cd ~/pii-rewrite
rm -rf rewrite.git
git clone --mirror ~/nixos-config rewrite.git
cd rewrite.git
git rev-list --count --all
```

Erwartet: 450 oder mehr (449 plus die neuen Commits).

- [ ] **Schritt 4: Mailmap für die Autorenzeilen schreiben**

Datei `../mailmap.txt` im Scratchpad. Sie deckt alle drei Identitäten aus §2 der
Spec ab, einschließlich der Variante mit Komma statt Punkt in der TLD:

```
NixOS User <user@posteo.de> <MAIL-mit-Punkt-TLD>
NixOS User <user@posteo.de> <MAIL-mit-Komma-TLD>
NixOS User <user@posteo.de> achimcc <MAIL-mit-Punkt-TLD>
```

Das dritte Feldpaar fängt die Commits ab, die unter dem GitHub-Namen als Autor
liefen.

- [ ] **Schritt 5: Rewrite ausführen**

```bash
cd ~/pii-rewrite/rewrite.git
nix run nixpkgs#git-filter-repo -- \
  --replace-text ../replacements.txt \
  --mailmap ../mailmap.txt \
  --path-rename home-<USER>.nix:home.nix \
  --force
echo "Exit: $?"
```

Erwartet: `Exit: 0` und eine Fortschrittsausgabe über alle Commits.

- [ ] **Schritt 6: Gegenprobe — jede Variante aus §2.2 der Spec**

Diese Prüfung ist die einzige, die den Rewrite validiert. Sie läuft über die
vollständige Variantenliste, nicht über eine Auswahl:

```bash
cd ~/pii-rewrite/rewrite.git
git grep -l -i -P "$U(?!cc)" $(git rev-list --all) | head
echo "---"
git log --all --format='%an <%ae>' | sort -u
echo "---"
git log --all --format='' --name-only | sort -u | grep -i "$U"
```

Erwartet:
1. keine Ausgabe (kein Blob enthält den Namen mehr, außer `achimcc`)
2. nur `NixOS User <user@posteo.de>`
3. keine Ausgabe (kein Pfad trägt den Namen)

Schlägt Prüfung 1 fehl, nennt die Ausgabe Commit und Datei — die fehlende Regel
in `replacements.txt` ergänzen und ab Schritt 3 wiederholen.

- [ ] **Schritt 7: Gegenprobe, dass `achimcc` überlebt hat**

```bash
cd ~/pii-rewrite/rewrite.git
git grep -c achimcc HEAD -- flake.nix
```

Erwartet: mindestens `1` — der Input-URL des privaten Repos. Eine `0` bedeutet,
dass der Lookahead nicht gegriffen hat und alle GitHub-URLs zerstört sind.

- [ ] **Schritt 8: Halt vor dem Push**

Der nächste Schritt ist unumkehrbar. Bis hierher ist nichts nach außen gelangt —
das Ergebnis liegt allein im Scratchpad. **Erst nach ausdrücklicher Freigabe
weitergehen.**

---

### Task 8: Veröffentlichen und nacharbeiten

- [ ] **Schritt 1: Push**

```bash
cd ~/pii-rewrite/rewrite.git
git remote add origin git@github.com:achimcc/nixos-config.git
git push --force --all
git push --force --tags
```

- [ ] **Schritt 2: Auf GitHub gegenprüfen**

```bash
gh api repos/achimcc/nixos-config/commits --jq '.[0].commit.author'
```

Erwartet: `NixOS User <user@posteo.de>`.

- [ ] **Schritt 3: Lokalen Checkout ersetzen**

Der alte Checkout hat keinen gemeinsamen Vorfahren mehr mit dem Remote:

```bash
cd ~/Projects
mv ~/nixos-config ~/nixos-config.alt
git clone git@github.com:achimcc/nixos-config.git ~/nixos-config
cd ~/nixos-config
git log --oneline -3
```

`nixos-config.alt` erst löschen, wenn ein Rebuild aus dem neuen Klon
nachweislich durchläuft — er ist die einzige verbliebene Kopie der alten Historie.

- [ ] **Schritt 4: Aus dem neuen Klon bauen**

```bash
cd ~/nixos-config
nix flake update identity
sudo nixos-rebuild switch --flake .#nixos
echo "Exit: $?"
```

Erwartet: `Exit: 0`.

- [ ] **Schritt 5: Alte Kopie entfernen**

Erst nach bestandenem Schritt 4:

```bash
rm -rf ~/nixos-config.alt
```

- [ ] **Schritt 6: Was bewusst offen bleibt**

Diese Punkte sind laut §9 der Spec **nicht** Teil der Arbeit und werden nur
festgehalten:

- Alle 449 Commit-Signaturen sind weg. Neusignieren wäre ein eigenes Vorhaben.
- Verwaiste Commits bleiben bei GitHub per Hash-URL erreichbar, bis der Support
  sie einsammelt. Wer das will, stellt die Anfrage manuell.
- `achimcc` bleibt in URL, Profil und Contribution-Graph sichtbar.
- Das private `homeserver`-Repo enthält dieselben Daten — es ist privat, und das
  genügt.
