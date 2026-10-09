# CLAUDE.md — nixos-config

NixOS-Flake für einen Laptop (`nixosConfigurations.nixos`, ThinkPad T14 Gen 5), Home Manager als
NixOS-Modul. Schwerpunkt Härtung: VPN-Kill-Switch, nftables, Secure Boot, FIDO2-LUKS.

`AGENTS.md` verweist nur noch hierher. Nutzerdokumentation ist `README.md`.

## Die Systemkonfiguration wird nicht von einer Sitzung gebaut

Der Rebuild (`nrs` = `nixos-rebuild switch --flake ~/nixos-config#nixos --sudo`) braucht root, und
root braucht den FIDO2-Stick mit PIN und Berührung. Das lässt sich aus einer Tool-Shell nicht
liefern.

- **Kein `nixos-rebuild`** in irgendeiner Form (`switch`, `test`, `build`, `dry-build`).
- **Kein Ersatzbau als Nutzer**: auch kein
  `nix build .#nixosConfigurations.nixos.config.system.build.toplevel` — weder im Vordergrund noch
  im Hintergrund, auch nicht „nur zur Verifikation".
- `nrs` startet der Nutzer selbst. Änderung übergeben, klar sagen, was belegt ist und was nicht,
  auf seine Ausgabe warten.
- Erlaubt zum Prüfen eines Fixes: **ein einzelnes Paket** bauen oder einen Wert auswerten (unten).

## Kommandos

```bash
# Einzelnes Paket mit den Overlays des Systems bauen
nix build '.#nixosConfigurations.nixos.pkgs.<attr>' --no-link --print-out-paths

# Einen Wert der Konfiguration auswerten
nix eval '.#nixosConfigurations.nixos.config.<option>'

# Baulog eines gescheiterten Derivats
nix log /nix/store/<hash>-<name>.drv

# Formatieren
nixpkgs-fmt <datei>.nix

# Privaten Identitäts-Input holen (als Nutzer, vor dem Rebuild)
nix flake update identity
```

`nix flake check` und volle Auswertungen sind schwer (bis 12 GB): über
`lotse run --class=eval -- <kommando>`; der PreToolUse-Hook setzt das meist selbst davor.

## Aufbau

| Pfad | Inhalt |
|------|--------|
| `flake.nix` | Inputs, Overlay, `nixosConfigurations.nixos`, `checks` |
| `configuration.nix` | Boot, Kernel-Parameter, Systempakete; importiert `modules/` |
| `home.nix` | Home Manager: Nutzerpakete, Programme, Nutzerdienste, Sandbox-Wrapper |
| `modules/*.nix` | Ein Thema je Datei (firewall, network, vpn, security, power, suricata, sops, …) |
| `modules/home/` | Home-Manager-Teilmodule |
| `pkgs/default.nix` | Eigenes Overlay: eigene Pakete **und** Korrekturen an nixpkgs-Paketen |
| `pkgs/<name>/` | Eigene Pakete (`shadow`, `hs-riegel`, `elster-mcp-server`) |
| `secrets/` | sops-verschlüsselte Geheimnisse |
| `docs/` | Verfahren, Härtung, Pläne (`docs/superpowers/plans/`) |
| `hardware-configuration.nix` | Generiert — nicht von Hand ändern |

Inputs: `nixpkgs` = `nixos-unstable` (26.11), `nixpkgs-unstable` zusätzlich als `pkgs-unstable`,
`home-manager` folgt `nixpkgs`, dazu `sops-nix`, `lanzaboote`, `nix-flatpak`, `llm-agents`,
`gestalt`, `lotse` und der private Input `identity`.

## Konventionen

- Kommentare, Commit-Nachrichten und Dokumente auf Deutsch; Commits im Imperativ, signiert.
- Abschnittsköpfe im Stil `# ==========`, Paketlisten mit `with pkgs;`.
- Systemweites nach `configuration.nix` / `modules/`, Nutzerbezogenes nach `home.nix`.
- Jede Abweichung von nixpkgs (Override, abgeschalteter Test) bekommt einen Kommentar mit Datum,
  Ursache und der Bedingung, unter der sie wieder entfällt.
- `README.md` mitziehen, wenn sich Module, Geheimnisse, Anwendungen, Tastenkürzel oder
  Sicherheitsmerkmale ändern.

## Fallstricke

- **Hostname:** `networking.hostName` (`modules/network.nix`) muss zu
  `nixosConfigurations.<name>` in `flake.nix` passen.
- **`stateVersion` bleibt `"24.11"`** (System und Home) — das ist der Installationsstand, nicht die
  nixpkgs-Version.
- **`flake.lock` gehört ins Repo.** `notify-updates.timer` aktualisiert und committet es täglich;
  ein gescheiterter Rebuild nach „flake.lock: Update" hat seine Ursache meist dort
  (`git show <commit> -- flake.lock`).
- **Identität** (Nutzername, Klarname, Mailadresse) kommt als `id.*` aus dem privaten Input
  `identity`, nicht aus sops: sops entschlüsselt zur Laufzeit, Nix wertet zur Bauzeit aus. root hat
  den SSH-Schlüssel nicht, deshalb holt der Nutzer den Input vor dem Rebuild selbst.
- **sops:** bearbeiten nur mit
  `sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml`. sops-nix prüft
  zur Bauzeit — erst das Geheimnis eintragen, dann die Konfiguration, die es nutzt.
- **Neue Dateien:** Nix sieht im Flake nur, was git kennt (`git add`). Parallele Sitzungen
  committen den ganzen Index mit — eine neue Datei deshalb sofort selbst committen.
- **Nicht-Standard-Python baut lokal.** `python3` ist 3.14; Hydra baut `python312Packages` nicht
  mehr vollständig. Wer 3.12 zieht (`apostrophe`, von nixpkgs so gepinnt), baut die
  Abhängigkeitskette lokal samt Tests — Zeitmesstests kippen unter Last, ein Python-Patchrelease
  kann sie brechen. Vor einer Versionswahl den Cache fragen:
  `curl -s -o /dev/null -w '%{http_code}' https://cache.nixos.org/<hash>.narinfo` (200 = vorhanden).
- **`--no-link`-Bauten überleben nicht.** `min-free`/`max-free` (`configuration.nix`) lassen den
  Daemon selbst aufräumen, sobald unter 20 GiB frei sind; alles ohne GC-Wurzel verschwindet. Ein
  Vorab-Bau spart dem nächsten `nrs` dann nichts.
- **Neuer Flake-Input:** in `inputs` eintragen, in die Parameter von `outputs` aufnehmen, über
  `specialArgs` (System) bzw. `home-manager.extraSpecialArgs` (Home) durchreichen, dann
  `nix flake lock`.
- **Kill-Switch:** ohne VPN ist das Netz absichtlich zu. „Kein Internet" ist dann kein Fehler.
- **GPU-Beschleunigung ist Pflicht** (HD-Video) — kein `nomodeset`.
- **Härtung messen, nicht lesen:** eine gesetzte Option heißt nicht, dass sie am System wirkt.
  Zustand am laufenden System prüfen.
