# SSH-Schlüssel ins TPM — Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Ziel:** Die zwei SSH-Schlüssel, mit denen Colmena und Claude selbstständig an den Homeserver gehen,
liegen nicht mehr als kopierbare Datei in `~/.ssh`, sondern versiegelt im TPM — benutzbar ohne
Rückfrage, aber nicht mitnehmbar.

**Architektur:** `ssh-tpm-agent` (Home-Manager-Modul `services.ssh-tpm-agent`) wird der Agent der
Sitzung; er hält die TPM-Schlüssel und reicht alles andere an den bisherigen `ssh-agent` durch (`-A`).
Zwei **neue** ECDSA-P-256-Schlüssel ersetzen `id_ed25519` und `id_ed25519_colmena`. Ablauf ohne
Aussperren: neue Schlüssel *zusätzlich* eintragen → umstellen → messen → alte austragen → alte löschen.

**Tech Stack:** NixOS 26.11 + Home Manager, ssh-tpm-agent 0.9.0, OpenSSH 10.5, Colmena (Homeserver-Repo),
`gh` (Token hat `admin:public_key`, `admin:ssh_signing_key`).

**Spec:** Entscheidung im Chat vom 2026-09-23 (Audit 2026-09-19, Befund „SSH-Schlüssel ohne
Passphrase"). Vorgaben des Nutzers: Colmena und Claude arbeiten weiter **selbstständig** am Server;
**neue** Schlüssel statt Import; Änderungen im Homeserver-Repo erlaubt.

## Global Constraints

- Keine Rückfrage beim Benutzen der Schlüssel: **keine TPM-PIN, keine Passphrase** (`-N ""`).
- Neue Dateinamen beginnen mit `id_` — AppArmor sperrt `@{HOME}/.ssh/id_*` für Browser/Sandkästen
  (`modules/apparmor-profiles.nix:331`).
- Schlüsseltyp ECDSA P-256 (TPM kann kein Ed25519). Fallback RSA-3072 nur, wo ein Gegenüber ECDSA ablehnt.
- Nie ein privater Schlüssel oder Token im Chat; öffentliche Schlüssel sind unkritisch.
- Jede volle Auswertung über `lotse run --class=eval -- …`; vor Messungen am Server `lotse wait deploy`.
- Alte Schlüssel erst löschen, wenn der neue Weg für **jedes** Ziel gemessen ist.
- Kommentare/Commits deutsch; Commits nur mit den Pfaden der eigenen Dateien (`git commit -- <pfade>`).

## Review Focus

1. **Wezterm-Agent:** In WezTerm zeigt `SSH_AUTH_SOCK` auf `wezterm/agent.*`, einen Proxy auf den Agent,
   den WezTerm beim Start sah. Erwartet: nach Neuanmeldung listet `ssh-add -l` im WezTerm die
   TPM-Schlüssel. Test in Task 2, Schritt 6.
2. **Sandkästen (VSCodium-bwrap, Claude darin):** `git push` und `ssh root@server` im Codium-Terminal
   müssen weiter gehen. Test in Task 4, Schritt 5.
3. **sftp-01 mit `IdentityAgent none`:** Dieser Block liest den Schlüssel direkt aus der Datei — mit
   TPM-Schlüssel geht das nicht. Erwartet: Nautilus/`sftp` klappt weiter. Test in Task 4, Schritt 4.
4. **Commit-Signaturen:** Alte Commits (mit `id_ed25519` signiert) müssen lokal und bei GitHub
   „verifiziert" bleiben, neue werden mit dem TPM-Schlüssel signiert. Test in Task 5.
5. **Aussperren:** Nach dem Austragen der alten Schlüssel muss root- UND colmena-Zugang zum Server gehen,
   bevor die alten Dateien gelöscht werden; der Nitrokey-Schlüssel (`admin@nitrokey`) bleibt als
   Notweg eingetragen. Test in Task 6, Schritt 3.

---

## Ausgangslage (gemessen 2026-09-23)

| Datei | Kommentar | Wo eingetragen | Schicksal |
|---|---|---|---|
| `id_ed25519` | achim.schneider@posteo.de | Server root + admin (`hosts/server/default.nix:263,295`), Rescue (`rescue/default.nix:144`), Router-Image (`lib/router.nix:276`), sftp-01 (`hosts/server/gaeste/sftp-01.nix:185`), GitHub, GitLab, Git-Signatur | → `id_ecdsa` (TPM) |
| `id_ed25519_colmena` | colmena-deploy@workstation | `hosts/server/deploy.nix:18` | → `id_ecdsa_colmena` (TPM) |
| `id_ed25519_initrd` | initrd-unlock | nur `~/Projects/proxmox` (verlorener Vorgänger) | löschen |
| `proxmox_github_deploy` | proxmox-autoupgrade | nirgends in den Repos | GitHub-Deploy-Keys prüfen, löschen |
| `hetzner-vps` | achim@hetzner-vps | VPS, kommt aus sops | **außerhalb dieses Plans** |
| `id_ed25519_sk` | admin@nitrokey | Notweg | bleibt |

Server-sshd hat keine `PubkeyAcceptedAlgorithms`-Einschränkung → ECDSA wird angenommen.
Router (dropbear, OpenWrt 25.12): ECDSA-Unterstützung **nicht gemessen**; außerdem scheitert
`ssh -F ssh_config router` derzeit mit `Host key verification failed` (vor diesem Plan, eigener Befund).

---

### Task 1: TPM-Zugang und ssh-tpm-agent auf dem Laptop

**Files:**
- Modify: `modules/secureboot.nix` (Abschnitt TPM 2.0) — `security.tpm2.enable`, Gruppe `tss`
- Modify: `home.nix:96-99` (`SSH_AUTH_SOCK` raus), `home.nix:378-392` (eigene `ssh-agent`-Unit →
  `services.ssh-agent`), neu `services.ssh-tpm-agent`
- Modify: `README.md` (Security Features)

**Interfaces:**
- Produces: Socket `$XDG_RUNTIME_DIR/ssh-tpm-agent.sock` als `SSH_AUTH_SOCK` der Sitzung; Fallback-Agent
  unter `$XDG_RUNTIME_DIR/ssh-agent`; Nutzer in Gruppe `tss`.

- [ ] **Schritt 1: Ausgangsmessung festhalten**

```bash
id | tr ',' '\n' | rg tss; ls -l /dev/tpmrm0; systemctl --user is-active ssh-agent
```
Erwartet: keine `tss`-Zeile, `/dev/tpmrm0` = `root root 0600`, `active`.

- [ ] **Schritt 2: TPM freigeben** — in `modules/secureboot.nix` unter „TPM 2.0 UND LUKS":

```nix
  # TPM2 für SSH-Schlüssel (ssh-tpm-agent, home.nix). Gruppe `tss` darf
  # /dev/tpmrm0 benutzen. LUKS hängt seit 2026-09-13 nicht mehr am TPM,
  # das TPM hält nur noch diese Schlüssel.
  security.tpm2 = {
    enable = true;
    pkcs11.enable = false;
  };
  users.users.${id.username}.extraGroups = [ config.security.tpm2.tssGroup ];
```

- [ ] **Schritt 3: Agent umstellen** — in `home.nix` die eigene Unit `systemd.user.services.ssh-agent`
  und `home.sessionVariables.SSH_AUTH_SOCK` entfernen, ersetzen durch:

```nix
  # SSH-Agenten (2026-09-23): ssh-tpm-agent ist der Agent der Sitzung und hält
  # die TPM-versiegelten Schlüssel ~/.ssh/*.tpm — benutzbar ohne Rückfrage,
  # aber nicht kopierbar. Alles andere (Nitrokey, hetzner-vps) reicht er an den
  # gewöhnlichen ssh-agent durch (-A). SSH_AUTH_SOCK setzt das HM-Modul.
  services.ssh-agent.enable = true;
  services.ssh-tpm-agent.enable = true;
```

- [ ] **Schritt 4: Auswerten und bauen**

```bash
lotse run --class=eval -- nix build --no-link --print-out-paths .#nixosConfigurations.nixos.config.system.build.toplevel
```
Erwartet: `lotse: exit=0`; die Assertion des HM-Moduls (Gruppe `tss`) schlägt NICHT an.

- [ ] **Schritt 5: Nutzer schaltet und meldet sich neu an** (Gruppe greift erst mit neuer Sitzung)

```nu
sudo nixos-rebuild switch --flake ~/nixos-config#nixos
```
Danach ab- und wieder anmelden.

- [ ] **Schritt 6: Messen**

```bash
id | tr ',' '\n' | rg tss
ls -l /dev/tpmrm0
systemctl --user is-active ssh-tpm-agent.socket ssh-agent
echo "$SSH_AUTH_SOCK"; systemctl --user show-environment | rg SSH_AUTH_SOCK
ssh-tpm-keygen --supported
```
Erwartet: `tss` vorhanden, `/dev/tpmrm0` Gruppe `tss` rw, beide `active`, `SSH_AUTH_SOCK` endet auf
`ssh-tpm-agent.sock` (im WezTerm: `wezterm/agent.*`, siehe Review Focus 1), `--supported` listet ecdsa.

- [ ] **Schritt 7: Commit**

```bash
git commit -m "SSH: ssh-tpm-agent als Sitzungsagent, TPM für Nutzergruppe tss" -- modules/secureboot.nix home.nix README.md
```

---

### Task 2: Neue TPM-Schlüssel erzeugen

**Files:** keine Repo-Dateien; erzeugt `~/.ssh/id_ecdsa.{tpm,pub}`, `~/.ssh/id_ecdsa_colmena.{tpm,pub}`.

**Interfaces:**
- Consumes: laufender ssh-tpm-agent aus Task 1.
- Produces: öffentliche Schlüssel `~/.ssh/id_ecdsa.pub` (Kommentar = `id.email`) und
  `~/.ssh/id_ecdsa_colmena.pub` (Kommentar `colmena-deploy@nixos-tpm`), beide im Agent.

- [ ] **Schritt 1: Erzeugen**

```bash
ssh-tpm-keygen -t ecdsa -N "" -C "$(git config user.email)" -f ~/.ssh/id_ecdsa
ssh-tpm-keygen -t ecdsa -N "" -C "colmena-deploy@nixos-tpm" -f ~/.ssh/id_ecdsa_colmena
```

- [ ] **Schritt 2: Agent neu laden und prüfen**

```bash
systemctl --user restart ssh-tpm-agent.service
ssh-add -l
```
Erwartet: zwei `ECDSA`-Zeilen mit den neuen Kommentaren (plus die alten Ed25519 über `-A`).

- [ ] **Schritt 3: Nicht kopierbar — Gegenprobe**

```bash
head -c 40 ~/.ssh/id_ecdsa.tpm | od -c | head -2
ssh-keygen -y -P "" -f ~/.ssh/id_ecdsa.tpm 2>&1 | head -1
```
Erwartet: `-----BEGIN TSS2 PRIVATE KEY-----`; `ssh-keygen` kann den Schlüssel NICHT lesen
(„invalid format" o. ä.) — er ist ein TPM-Blob, kein OpenSSH-Schlüssel.

- [ ] **Schritt 4: Fingerabdrücke für die folgenden Tasks notieren**

```bash
for f in ~/.ssh/id_ecdsa.pub ~/.ssh/id_ecdsa_colmena.pub; do ssh-keygen -lf "$f"; done
```

- [ ] **Schritt 5: Im WezTerm sichtbar** (Review Focus 1): in einem NEUEN WezTerm-Fenster `ssh-add -l`
  → beide ECDSA-Schlüssel stehen drin.

---

### Task 3: Neue Schlüssel im Homeserver ZUSÄTZLICH eintragen und deployen

**Files (Repo `~/Projects/homeserver`):**
- Modify: `hosts/server/default.nix:263` (root) und `:295` (admin)
- Modify: `hosts/server/deploy.nix:18` (`colmenaDeployPubkey` → Liste)
- Modify: `hosts/server/gaeste/sftp-01.nix:185` (`achim`)
- Modify: `rescue/default.nix:144`
- Modify: `lib/router.nix:276` (wirkt erst beim nächsten Image — siehe Task 7)

**Interfaces:**
- Consumes: Inhalt von `~/.ssh/id_ecdsa.pub` und `~/.ssh/id_ecdsa_colmena.pub` (Task 2).
- Produces: Server akzeptiert alten UND neuen Schlüssel für root, admin, colmena-deploy, sftp achim.

- [ ] **Schritt 1:** Homeserver-`CLAUDE.md` lesen, `lotse status`, eigenen Worktree nutzen, falls dort
  eine andere Sitzung arbeitet.

- [ ] **Schritt 2: Eintragen** — neben jede alte `ssh-ed25519 … achim.schneider@posteo.de`-Zeile die
  Zeile aus `~/.ssh/id_ecdsa.pub`, mit Kommentar darüber:

```nix
    # TPM-versiegelt auf der Workstation (ssh-tpm-agent, seit 2026-09-23).
    # Die Ed25519-Zeile darüber fliegt raus, sobald der neue Weg gemessen ist.
    "ecdsa-sha2-nistp256 AAAA… <id.email>"
```
In `deploy.nix`:

```nix
  # Seit 2026-09-23 TPM-versiegelt auf der Workstation; der Ed25519-Schlüssel
  # bleibt nur bis zur Messung des neuen Wegs stehen.
  colmenaDeployPubkeys = [
    "ssh-ed25519 AAAA… colmena-deploy@workstation"
    "ecdsa-sha2-nistp256 AAAA… colmena-deploy@nixos-tpm"
  ];
  …
    openssh.authorizedKeys.keys = colmenaDeployPubkeys;
```
Prüfen, ob `colmenaDeployPubkey` sonst noch referenziert wird: `rg -n colmenaDeployPubkey`.

- [ ] **Schritt 3: Checks des Repos** (so, wie die Homeserver-`CLAUDE.md` es vorschreibt), dann deployen
  über den dort beschriebenen Weg (`scripts/deploy.sh` / `just`), unter `lotse`.

- [ ] **Schritt 4: Messen, mit NEUEM Schlüssel, alter ausdrücklich nicht angeboten**

```bash
lotse wait deploy
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ecdsa.pub root@server.taile9e283.ts.net 'echo ok-root'
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ecdsa_colmena.pub colmena-deploy@server.taile9e283.ts.net 'echo ok-deploy'
ssh root@server.taile9e283.ts.net 'journalctl -u sshd --since "-5min" | rg "Accepted publickey" | tail -2'
```
Erwartet: `ok-root`, `ok-deploy`, Journal zeigt `ECDSA SHA256:<Fingerabdruck aus Task 2>`.

- [ ] **Schritt 5: Commit im Homeserver-Repo** (nur die geänderten Pfade).

---

### Task 4: Clients auf die neuen Schlüssel umstellen

**Files:**
- Modify: `home.nix:1001-1130` (`programs.ssh.settings`: jedes `IdentityFile ~/.ssh/id_ed25519` →
  `~/.ssh/id_ecdsa.pub`, `id_ed25519_colmena` → `id_ecdsa_colmena.pub`; sftp-Block: `IdentityAgent none`
  → Socket des ssh-tpm-agent)
- Modify (Homeserver): `ssh_config:85,90,191,198` analog

**Interfaces:**
- Consumes: Schlüssel aus Task 2, Server-Freigaben aus Task 3.

- [ ] **Schritt 1: `IdentityFile` auf die `.pub`-Dateien.** Bei TPM-Schlüsseln zeigt `IdentityFile` auf den
  öffentlichen Teil; ssh sucht den passenden privaten Teil im Agent. `IdentitiesOnly yes` bleibt.

- [ ] **Schritt 2: sftp-01-Block** — `IdentityAgent = "none"` ersetzen durch
  `IdentityAgent = "\${XDG_RUNTIME_DIR}/ssh-tpm-agent.sock";` und den Kommentar darüber anpassen: Der Block
  wollte verhindern, dass ssh sieben Agent-Schlüssel durchprobiert; `IdentitiesOnly yes` + `.pub`
  leistet das jetzt, der Agent ist nötig, weil der private Teil nur dort liegt.

- [ ] **Schritt 3: Bauen, schalten** (Nutzer: `sudo nixos-rebuild switch …`), dann `ssh -G` prüfen:

```bash
ssh -G server.taile9e283.ts.net | rg '^(identityfile|identityagent|identitiesonly)'
ssh -G sftp.rusty-vault.de | rg '^(identityfile|identityagent|identitiesonly)'
```

- [ ] **Schritt 4: Jedes Ziel messen** (`-v`, damit der angenommene Schlüssel sichtbar ist)

```bash
for h in server.taile9e283.ts.net 10.10.20.1 100.72.129.125; do ssh -v -o BatchMode=yes "$h" true 2>&1 | rg 'Server accepts key|Authenticated to' | head -2; done
cd ~/Projects/homeserver && ssh -F ssh_config -v -o BatchMode=yes server true 2>&1 | rg 'Server accepts key'
echo 'ls' | sftp -b - -o BatchMode=no sftp.rusty-vault.de 2>&1 | head -3
```
Erwartet überall `ECDSA SHA256:<neu>`; sftp listet das Verzeichnis. (Welche Hosts in `10.10.*`
tatsächlich existieren: aus `ssh_config`/Colmena-Hive des Homeserver-Repos nehmen.)

- [ ] **Schritt 5: Sandkasten** (Review Focus 2) — im VSCodium-Terminal:
  `ssh -o BatchMode=yes root@server.taile9e283.ts.net true && echo ok`. Scheitert es, weil der Socket im
  bwrap fehlt: im Wrapper (`home.nix` ~Zeile 1514) `--ro-bind $XDG_RUNTIME_DIR/ssh-tpm-agent.sock`
  ergänzen und erneut messen.

- [ ] **Schritt 6: Ein echter Colmena-Deploy** über `lotse` (Trockenlauf reicht nicht — der
  Closure-Push nutzt den Schlüssel). Erwartet: Erfolg, Journal zeigt den neuen Fingerabdruck.

- [ ] **Schritt 7: Commits** in beiden Repos.

---

### Task 5: GitHub, GitLab und Commit-Signatur

**Files:**
- Modify: `home.nix:1169-1200` (`signing.key` → `~/.ssh/id_ecdsa.pub`; `allowed_signers`: alte Zeile
  BEHALTEN, neue dazu)

- [ ] **Schritt 1: GitHub** (Token hat die Rechte):

```bash
gh ssh-key add ~/.ssh/id_ecdsa.pub --type authentication --title "nixos TPM (2026-09-23)"
gh ssh-key add ~/.ssh/id_ecdsa.pub --type signing --title "nixos TPM signing (2026-09-23)"
ssh -T -o IdentitiesOnly=yes -i ~/.ssh/id_ecdsa.pub git@github.com 2>&1 | head -1
```
Erwartet: `Hi achimcc! You've successfully authenticated`.

- [ ] **Schritt 2: GitLab** — Nutzer trägt `~/.ssh/id_ecdsa.pub` im Web ein (kein Token vorhanden).
  Messen: `ssh -T -o IdentitiesOnly=yes -i ~/.ssh/id_ecdsa.pub git@gitlab.com` (über den `altssh`-Block).

- [ ] **Schritt 3: Signatur umstellen**

```nix
    signing = {
      key = "~/.ssh/id_ecdsa.pub";   # TPM-versiegelt, Signatur über ssh-tpm-agent
```
`allowed_signers`: neue Zeile mit `namespaces="git" ecdsa-sha2-nistp256 …` dazu; die Ed25519-Zeile
bleibt, damit die Historie verifizierbar bleibt.

- [ ] **Schritt 4: Messen** (nach Switch)

```bash
git commit --allow-empty -m "Test: Signatur mit TPM-Schlüssel" && git log -1 --show-signature | head -3
git log --show-signature -1 8cbb863 | head -3
```
Erwartet: neuer Commit `Good "git" signature … ECDSA SHA256:<neu>`, alter Commit weiter `Good … ED25519`.
Den Test-Commit danach mit `git reset --soft HEAD~1` entfernen (noch nicht gepusht).

- [ ] **Schritt 5: Commit** der `home.nix`-Änderung (echter Commit, signiert mit dem neuen Schlüssel).

---

### Task 6: Alte Schlüssel austragen und löschen

**Files (Homeserver):** die Ed25519-Zeilen aus Task 3 entfernen, `colmenaDeployPubkeys` auf den
neuen Eintrag kürzen, Kommentare anpassen.

- [ ] **Schritt 1:** Homeserver-Zeilen entfernen, Checks, Deploy (unter `lotse`).

- [ ] **Schritt 2: Alter Schlüssel wird abgewiesen**

```bash
lotse wait deploy
ssh -o IdentitiesOnly=yes -o IdentityAgent=none -i ~/.ssh/id_ed25519 -o BatchMode=yes root@server.taile9e283.ts.net true; echo "exit=$?"
ssh -o IdentitiesOnly=yes -o IdentityAgent=none -i ~/.ssh/id_ed25519_colmena -o BatchMode=yes colmena-deploy@server.taile9e283.ts.net true; echo "exit=$?"
```
Erwartet: beide `Permission denied (publickey)`, `exit=255`.

- [ ] **Schritt 3: Neuer Weg geht noch** (Review Focus 5): Task 4 Schritt 4 wiederholen, außerdem
  bestätigen, dass `admin@nitrokey` weiter eingetragen ist: `rg -n 'sk-ssh-ed25519' ~/Projects/homeserver --glob '*.nix'`.

- [ ] **Schritt 4: GitHub/GitLab** — alten Schlüssel als *Authentifizierungs*-Schlüssel entfernen
  (`gh ssh-key list`, dann `gh ssh-key delete <id>`); als *Signier*-Schlüssel stehen lassen, damit alte
  Commits „Verified" bleiben. `proxmox_github_deploy`: `gh api /repos/achimcc/<repo>/keys` für die
  Proxmox-Repos, gefundenen Deploy-Key löschen.

- [ ] **Schritt 5: Dateien löschen**

```bash
rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_colmena ~/.ssh/id_ed25519_initrd ~/.ssh/proxmox_github_deploy
ssh-add -D   # alte Kopien aus dem Fallback-Agent
ssh-add -l
```
Erwartet: `ssh-add -l` zeigt nur noch die zwei ECDSA-TPM-Schlüssel (+ ggf. Nitrokey/hetzner, wenn benutzt).
Die `.pub`-Dateien der alten Schlüssel bleiben (für `allowed_signers` unkritisch).

- [ ] **Schritt 6: Doku**
  - `~/.claude/CLAUDE.md` Abschnitt „Diese Workstation": `~/.ssh/id_ed25519` → `~/.ssh/id_ecdsa`
    (TPM), Signierung ebenso.
  - Homeserver-`CLAUDE.md`/Kommentare, die `id_ed25519` als Diagnoseweg nennen.
  - `README.md` (Security Features): TPM-Schlüssel, Notweg Nitrokey, TPM-Reset = Schlüssel weg.
  - Memory-Notiz zum Audit aktualisieren.

- [ ] **Schritt 7: Commits** in beiden Repos.

---

### Task 7: Router (gesperrt, bis der Hostkey-Befund geklärt ist)

`ssh -F ssh_config router` scheitert heute mit `Host key verification failed`. Das wird NICHT durch
Überschreiben von `known_hosts` gelöst, sondern erst geklärt (neu geflasht? anderer Hostkey im Image?).

- [ ] **Schritt 1:** Hostkey-Befund klären — Fingerabdruck des Routers (über den Server:
  `ssh root@server 'ssh-keyscan -t ed25519 192.168.20.1'`) gegen den im Image/`known_hosts` vergleichen.
- [ ] **Schritt 2:** ECDSA bei dropbear testen:
  `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ecdsa.pub -F ~/Projects/homeserver/ssh_config router true`.
  Lehnt dropbear ECDSA ab: zusätzlich `ssh-tpm-keygen -t rsa -b 3072 -N "" -f ~/.ssh/id_rsa_router`
  und diesen für `Host router*` verwenden.
- [ ] **Schritt 3:** Schlüssel in `lib/router.nix` (fürs nächste Image) UND einmalig live in
  `/etc/dropbear/authorized_keys` — das Image ist die deklarative Quelle, ein Neuflashen nur für einen
  Schlüssel ist unverhältnismäßig; im Kommentar in `lib/router.nix` festhalten.
- [ ] **Schritt 4:** Messen wie Task 6 Schritt 2/3, dann alte Zeile aus `lib/router.nix` und live entfernen.

Bis Task 7 erledigt ist, bleibt der alte `id_ed25519` für den Router nötig → **Task 6 Schritt 5
löscht `id_ed25519` erst nach Task 7** (die anderen drei Dateien dürfen vorher weg).
