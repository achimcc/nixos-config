# WireGuard-Profile mit Kill-Switch und Leistenanzeige statt ProtonVPN-GUI — Umsetzungsplan

> **Für agentische Bearbeiter:** ERFORDERLICHE UNTER-SKILL: `superpowers:subagent-driven-development`
> (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Schritte nutzen
> Checkbox-Syntax (`- [ ]`).

**Ziel:** Neun Proton-WireGuard-Profile im NetworkManager, per `Super+Alt+1…9` / `Super+Alt+0`
und per Klick-Menü in der GNOME-Leiste umschaltbar, mit gemessenem Zustand in der Leiste und einem
Kill-Switch; die ProtonVPN-GUI verschwindet vollständig.

**Architektur:** Ein Befehl `vpn` ist der einzige Umschaltpfad (Kürzel, Menü, Terminal). Ein
root-Dienst `vpn-status` misst alle 2 s (`wg`, `nft`) und schreibt `/run/vpn/status.json`; die
Shell-Erweiterung `vpn-indikator@local` liest nur Dateien und ruft nur `vpn` auf. Der Kill-Switch
ist die nftables-Output-Chain mit `policy drop`; der Zustand „Direkt“ ist eine Chain `direkt`,
die `vpn-direkt.service` füllt.

**Tech-Stack:** NixOS (Flake), NetworkManager 1.58 (`ensureProfiles`, envsubst), sops-nix
(Templates), nftables, polkit, home-manager (dconf), GNOME Shell 50 (ESM-Erweiterung), gjs,
bash (`writeShellApplication` → shellcheck beim Bau).

**Spec:** `docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md`

## Fortschritt

| Aufgabe | Stand | Beleg |
|---|---|---|
| 1 Serverdaten | erledigt | `771034b`; homeserver-secrets `a6a3ee8` |
| 2 Profile + Messungen | erledigt | `dec3511`; Tunnel trägt (Exit-Land/-Organisation ≠ Heimanbieter); resolved ohne eigenes DNS/`~.` am Link, Abfrage `authenticated: yes`; `rp_filter=2`; Proton-Resolver (10.2.0.1) validiert DNSSEC nicht (`dnssec-failed.org` → `NOERROR` ohne `ad`-Flag, `. DNSKEY`-Anfrage mit `+dnssec` scheitert `NOTIMP` → 0 RRSIG) und filtert `doubleclick.net` nicht (DNS-seitig kein NetShield-Effekt); Quad9 löst `doubleclick.net` normal auf. Empfehlung: DNS vorerst bei Quad9/Mullvad belassen, nicht auf Proton umstellen. |
| 3 Status + Direkt | erledigt | `8fa0ab0`, `a089a79`; Statusdatei `/run/vpn/status.json` 644 root, Felder vollständig (Slot, Name, Handshake-Alter, rx/tx, direkt, killswitch); Tunnel weg → `slot` null, danach wieder verbunden; Zustand „Direkt“ ohne Passwortabfrage gestartet/gestoppt (Tool-Bash in aktiver Sitzung); nftables-Neustart leert die Chain `direkt`, die Unit meldet danach weiterhin `active` → Wahrheit ist die Chain, nicht der Unit-Zustand (Verfeinerung 2), bestätigt. |
| 4 `vpn`-Befehl | erledigt | `f28ebb1`, `ab5eab3`; Review-Korrektur (gescheitertes Trennen/`vpn-direkt` jetzt gemessen statt vertraut, sichtbare Meldung, Exit-Code 1) im Re-Review ADDRESSED bestätigt. Nach Rebuild alle neun Slots einzeln geschaltet: acht von neun Slots mit passendem Exit-Land bestätigt, ein Slot (3) scheiterte an der Exit-IP-Prüfung nach zwei Versuchen (Profil blieb aktiv, kein Handshake-Nachweis) — Ursache noch offen, kein Blocker für die übrigen acht. Sperre gegen parallele Umschaltung hält (`exit=3`, nur ein Tunnel aktiv). `aus`/`direkt`/Rückkehr/`login` liefern exakt die erwarteten Statuswerte (`slot`/`direkt`), zweites `login` ohne erneute Umschaltung. Alltags-Slot 1 gesetzt (`direkt` false, genau ein Tunnel aktiv). |
| 5 Leiste, Kürzel, Login | offen | |
| 6 GUI raus | offen | |
| 7 Kill-Switch | offen | |
| 8 Doku | offen | |

## Globale Randbedingungen

- **Sprache:** Kommentare, Commit-Nachrichten, Meldungstexte deutsch.
- **Repo `nixos-config` ist öffentlich.** Keine Endpunkte, Servernamen, Schlüssel, Exit-IPs oder
  Heim-IP in Commits, Kommentaren oder Plan-Belegen. Serverliste nur in `homeserver-secrets`.
- **Beim Ansehen von Konfigurationen jede Wertzeile maskieren**
  (`sed -E 's/(: |=).*/\1<verdeckt>/'`). `PrivateKey` erscheint nie in einer Ausgabe.
- **Im Tool-Bash gibt es kein sudo** (`sudo: Ein Passwort ist notwendig`). Schritte mit
  `sudo` sind als **[Nutzer]** markiert; der Nutzer führt sie in seinem Terminal (Nushell) aus und
  meldet die Ausgabe zurück.
- **`nix build … | tail`** gibt tails Exit-Code zurück → ohne Pipe bauen oder `${PIPESTATUS[0]}`.
- **Vor jedem `sudo nixos-rebuild`**, wenn `homeserver-secrets` sich geändert hat:
  als Nutzer `nix flake update identity`.
- **Verifikation misst den Zustand**, nicht den Exit-Code (`nmcli` meldet bei WireGuard Erfolg
  ohne Handshake; `curl` gibt 0 bei 503 ohne `--fail`).
- **Slots:** genau 9, Nummern 1–9. NM-Profil und Interface heißen `wg-<n>`.
- **Grenzwerte:** Handshake „hängt“ ab **180 s**, Statusdatei „unbekannt“ ab **15 s** Alter,
  Exit-Prüfung **15 s** Timeout, `persistent-keepalive = 25`.
- **Dateien zur Laufzeit:** `/etc/vpn/server.json` (Slot + Name, 0644), `/run/vpn/status.json`
  (root, 0644), `$XDG_RUNTIME_DIR/vpn/exit.json`, `$XDG_RUNTIME_DIR/vpn/lock`,
  `${XDG_STATE_HOME:-~/.local/state}/vpn/letzter`.
- **Exit-IP-Dienst:** `https://am.i.mullvad.net/json` (Felder gemessen 2026-09-13: `ip`,
  `country`, `city`, `organization`, `mullvad_exit_ip`, `blacklisted`, `latitude`, `longitude`).
- **Stufe 1 (Aufgaben 1–6) lässt die Output-Chain auf `policy accept`.** Erst Aufgabe 7 schaltet
  `policy drop`, zuerst mit `nixos-rebuild test`.

## Verfeinerungen gegenüber der Spec (beim Planen entschieden)

1. **Kein NM-Autoconnect.** Alle Profile `autoconnect = false`; beim Boot verbindet
   `vpn-boot.service` einmal `wg-1`. Grund: Das Verhalten von NM-Autoconnect nach manuellem
   Trennen ist nicht belegt; ein expliziter Dienst ist es.
2. **Wahrheit für „Direkt“ ist der Inhalt der Chain `direkt`, nicht der Unit-Zustand.** Ein
   nftables-Reload (`nixos-rebuild`) leert die Chain per `flush ruleset`, die Unit bliebe aber
   „active“. `vpn direkt` benutzt deshalb `systemctl restart`, Status und `vpn` lesen die Chain.
   `PartOf=` entfällt (es würde Neustarts *weiterreichen*, also „Direkt“ wiederherstellen).
3. **Statusdatei unter `/run/vpn/status.json`** (eigenes `RuntimeDirectory`) statt
   `/run/vpn-status.json`; die Erweiterung fragt sie jede Sekunde ab statt Dateiüberwachung.
4. **Neues Statusfeld `killswitch`** (gemessen: `policy drop` in der Output-Chain). Ohne Tunnel und
   ohne Kill-Switch zeigt die Leiste `⚠ OFFEN` rot statt `⛔ gesperrt` — sonst würde die Anzeige
   in Stufe 1 eine Sperre behaupten, die es nicht gibt.
5. **Syncthing-Ratenlimit steht vor der `established`-Regel**, sonst gilt es nur für das erste
   Paket jeder Verbindung.
6. **NetShield:** Konfigurationen werden mit NetShield Stufe 2 heruntergeladen (wirkt nur über
   Protons DNS, also vorerst nicht). Aufgabe 2 misst, ob `10.2.0.1` strenges DNSSEC trägt; die
   Entscheidung DNS = Quad9 oder Proton trifft danach der Nutzer.

## Dateiübersicht

| Datei | Aufgabe | Verantwortung |
|---|---|---|
| `homeserver-secrets/vpn/laptop.nix` | 1 | Serverliste (privat) |
| `secrets/secrets.yaml` → `wireguard/slot1…9` | 1 | private Schlüssel |
| `flake.nix` | 2, 6 | `vpnServer` an NixOS und home-manager; Proton-Overlay raus |
| `modules/vpn.nix` | 2, 3, 4 | Profile, SOPS, `/etc/vpn/server.json`, `vpn-boot`, `vpn-status`, `vpn-direkt`, polkit, `vpn` |
| `modules/vpn/vpn.sh` | 4 | Umschaltlogik |
| `modules/vpn/vpn-status.sh` | 3 | Messschleife |
| `modules/firewall.nix` | 3, 6, 7 | Chain `direkt`; Proton-Reste raus; Kill-Switch |
| `modules/home/vpn.nix` | 5 | Erweiterungspaket, Aktivierung, Kürzel, `vpn-login` |
| `modules/home/vpn-indikator/` | 5 | `metadata.json`, `extension.js`, `zustand.js`, `test-zustand.js`, `stylesheet.css` |
| `configuration.nix` | 2, 6 | Import `vpn.nix` statt `protonvpn.nix` |
| `modules/protonvpn.nix` | 6 | gelöscht |
| `modules/network.nix`, `home.nix`, `modules/email-alerts.nix`, `modules/sops.nix`, `modules/security.nix`, `modules/desktop.nix`, `modules/suricata.nix` | 6 | Proton-Reste |
| `docs/…` | 8 | Doku nachziehen |

---
## Aufgabe 1: Serverdaten ins private Repo, Schlüssel in SOPS

**Dateien:**
- Erstellen: `~/Projects/homeserver-secrets/vpn/laptop.nix`
- Ändern: `secrets/secrets.yaml` (neuer Zweig `wireguard/slot1…9`)
- Hilfsskripte nur im Scratchpad, **nicht** ins Repo: `serverliste-erzeugen.sh`, `schluessel-setzen.sh`

**Quelle:** `/home/achim/Dokumente/vpn/vpn-<slot>-<NAME>.conf` (9 Dateien, Rechte 600, Ordner 700).
Gemessen 2026-09-13: jede Datei hat genau eine `Address` mit IPv4 `/32` (sechs zusätzlich IPv6),
`Endpoint` als `IPv4:51820`, `AllowedIPs = 0.0.0.0/0, ::/0`, `PersistentKeepalive = 25`,
`# NetShield = 2`, `PublicKey` mit 44 Zeichen. Alle neun IPv4-Adressen sind identisch.

**Interfaces:**
- Produziert: Nix-Liste von 9 Attrsets
  `{ slot :: int 1..9; name :: string; endpoint :: IPv4-string; port :: int; serverPublicKey :: string; address :: "a.b.c.d/32"; }`
  und die SOPS-Schlüssel `wireguard/slot<n>` (je ein 44-Zeichen-Base64-String).

- [ ] **Schritt 1: Prüfen, dass die Liste noch fehlt (roter Test)**

```bash
nix-instantiate --eval --strict -E 'builtins.length (import /home/achim/Projects/homeserver-secrets/vpn/laptop.nix)'
```
Erwartet: Fehler `path '/home/achim/Projects/homeserver-secrets/vpn/laptop.nix' does not exist`.

- [ ] **Schritt 2: Erzeugungsskript in den Scratchpad schreiben**

`serverliste-erzeugen.sh` — liest `PrivateKey` nicht und gibt keine Werte aus:

```bash
#!/usr/bin/env bash
# Erzeugt die Serverliste für nixos-config/modules/vpn.nix aus den Proton-Downloads.
# Liest PrivateKey NICHT und gibt keine Werte aus.
set -euo pipefail
quelle=${1:?Ordner mit vpn-<slot>-<NAME>.conf}
ziel=${2:?Zieldatei}
{
  echo '# Serverliste für nixos-config/modules/vpn.nix — privat, mit Absicht NICHT verschlüsselt.'
  echo '# Wird zur BAUZEIT gebraucht (NM-Profile, Firewall-Regel für die Endpunkte); sops-nix'
  echo '# entschlüsselt erst zur Laufzeit. Private Schlüssel liegen NICHT hier, sondern in'
  echo '# nixos-config/secrets/secrets.yaml unter wireguard/slot<n>.'
  echo '# Erzeugt 2026-09-13 aus Proton-Downloads (NetShield 2, VPN Accelerator an).'
  echo '['
  for f in "$quelle"/vpn-[1-9]-*.conf; do
    base=$(basename "$f" .conf)
    slot=${base#vpn-}; slot=${slot%%-*}
    name=${base#vpn-"$slot"-}
    adresse=$(sed -nE 's/^Address *= *([0-9.]+\/32).*/\1/p' "$f")
    pub=$(sed -nE 's/^PublicKey *= *(.+)$/\1/p' "$f")
    read -r ip port < <(sed -nE 's/^Endpoint *= *([0-9.]+):([0-9]+)$/\1 \2/p' "$f")
    printf '  { slot = %s; name = "%s"; endpoint = "%s"; port = %s;\n    serverPublicKey = "%s"; address = "%s"; }\n' \
      "$slot" "$name" "$ip" "$port" "$pub" "$adresse"
  done
  echo ']'
} > "$ziel"
echo "geschrieben: $ziel"
```

- [ ] **Schritt 3: Liste erzeugen**

```bash
mkdir -p /home/achim/Projects/homeserver-secrets/vpn
bash <scratchpad>/serverliste-erzeugen.sh /home/achim/Dokumente/vpn /home/achim/Projects/homeserver-secrets/vpn/laptop.nix
```

- [ ] **Schritt 4: Liste prüfen (grüner Test) — nur Slots, Namen und Formprüfungen ausgeben**

```bash
nix-instantiate --eval --strict --json -E '
  let l = import /home/achim/Projects/homeserver-secrets/vpn/laptop.nix;
      ip = s: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" s != null;
  in {
    anzahl = builtins.length l;
    slots = builtins.sort builtins.lessThan (map (s: s.slot) l);
    namen = map (s: s.name) l;
    endpunkteSindIPv4 = builtins.all (s: ip s.endpoint) l;
    adressenSind32 = builtins.all (s: builtins.match "[0-9.]+/32" s.address != null) l;
    schluessel44 = builtins.all (s: builtins.stringLength s.serverPublicKey == 44) l;
    ports = builtins.attrNames (builtins.listToAttrs (map (s: { name = toString s.port; value = 1; }) l));
  }'
```
Erwartet: `anzahl` 9, `slots` `[1,…,9]`, 9 nicht-leere Namen, alle drei Booleans `true`, `ports` `["51820"]`.

- [ ] **Schritt 5: Schlüssel-Skript in den Scratchpad schreiben**

`schluessel-setzen.sh` — Werte laufen nur über stdin, nie über Argumente oder Ausgabe:

```bash
#!/usr/bin/env bash
# Schreibt die privaten WireGuard-Schlüssel nach secrets.yaml (wireguard/slot<n>).
# Werte laufen über stdin (sops set --value-stdin), nie über Argumente oder die Ausgabe.
set -euo pipefail
quelle=${1:?Ordner mit vpn-<slot>-<NAME>.conf}
datei=${2:?Pfad zu secrets.yaml}
for f in "$quelle"/vpn-[1-9]-*.conf; do
  base=$(basename "$f" .conf); slot=${base#vpn-}; slot=${slot%%-*}
  sed -nE 's/^PrivateKey *= *(.+)$/"\1"/p' "$f" | tr -d '\n' \
    | sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt \
        sops set --value-stdin "$datei" "[\"wireguard\"][\"slot$slot\"]"
  echo "slot$slot gesetzt"
done
```

- [ ] **Schritt 6: [Nutzer] Schlüssel setzen**

```nu
bash <scratchpad>/schluessel-setzen.sh /home/achim/Dokumente/vpn /home/achim/nixos-config/secrets/secrets.yaml
```
Erwartet: neun Zeilen `slot<n> gesetzt`.

- [ ] **Schritt 7: [Nutzer] Schlüssel prüfen — nur Slot und Länge**

```nu
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops -d --extract '["wireguard"]' /home/achim/nixos-config/secrets/secrets.yaml | awk -F': ' '{ print $1, length($2) }'
```
Erwartet: `slot1 44` … `slot9 44`.

Danach im Tool-Bash: `stat -c '%U %a' secrets/secrets.yaml` → Eigentümer ist der Nutzer (nicht
`root`). Falls `root`: **[Nutzer]** `sudo chown achim:users secrets/secrets.yaml`.

- [ ] **Schritt 8: Commits**

```bash
git -C /home/achim/Projects/homeserver-secrets add vpn/laptop.nix
git -C /home/achim/Projects/homeserver-secrets commit -m "Serverliste für die neun WireGuard-Slots des Laptops"
git -C /home/achim/nixos-config add secrets/secrets.yaml
git -C /home/achim/nixos-config commit -m "SOPS: private Schlüssel der neun WireGuard-Slots"
```
Beide Nachrichten mit den Attributionszeilen der Sitzung abschließen.

- [ ] **Schritt 9: Push des privaten Repos — vorher den Nutzer fragen**

```bash
git -C /home/achim/Projects/homeserver-secrets push
```
Nötig, weil der Flake-Input `identity` per `git+ssh` von GitHub kommt.

---

## Aufgabe 2: Tunnel-Profile, Boot-Verbindung und Messungen am ersten Tunnel

**Dateien:**
- Ändern: `flake.nix` (let-Block nach `id = import …`, `specialArgs`, `home-manager.extraSpecialArgs`)
- Erstellen: `modules/vpn.nix`
- Ändern: `configuration.nix:11` (Import ergänzen; `protonvpn.nix` bleibt bis Aufgabe 6)
- Lock: `flake.lock` (Input `identity`)

**Interfaces:**
- Konsumiert: Serverliste aus Aufgabe 1, SOPS-Schlüssel `wireguard/slot<n>`.
- Produziert: Modul-Argument `vpnServer` (NixOS **und** home-manager); NM-Profile `wg-1…wg-9`;
  `/etc/vpn/server.json` = `[{ "slot": 1, "name": "…" }, …]`; `vpn-boot.service`;
  `modules/vpn.nix` hat einen `let`-Block, in den Aufgaben 3 und 4 Pakete einfügen.

- [ ] **Schritt 1: `identity` aktualisieren und `vpnServer` durchreichen**

```bash
nix flake update identity
```

In `flake.nix` direkt unter `id = import "${identity}/identity/laptop.nix";`:

```nix
      # WireGuard-Serverliste aus dem PRIVATEN Repo (Slots 1–9). Bauzeit-Daten:
      # NM-Profile und die Firewall-Regel für die Endpunkte brauchen sie, bevor
      # sops-nix irgendetwas entschlüsselt. Schlüssel liegen in secrets.yaml.
      vpnServer = import "${identity}/vpn/laptop.nix";
```

`specialArgs = { inherit inputs llm-agents pkgs-unstable id vpnServer; };`
`home-manager.extraSpecialArgs = { inherit llm-agents pkgs-unstable rcu id vpnServer; };`

- [ ] **Schritt 2: Roter Test — Profile existieren in der Auswertung noch nicht**

```bash
nix eval --json .#nixosConfigurations.nixos.config.networking.networkmanager.ensureProfiles.profiles --apply 'p: builtins.filter (n: builtins.match "wg-[1-9]" n != null) (builtins.attrNames p)'
```
Erwartet: `[]`.

- [ ] **Schritt 3: `modules/vpn.nix` anlegen**

```nix
# WireGuard statt ProtonVPN-GUI: neun feste Proton-Server als NetworkManager-Profile.
# Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md
#
# Umgeschaltet wird nur über den Befehl `vpn` (Tastenkürzel, Leiste, Terminal).
# Die Serverliste kommt aus dem privaten Repo (Flake-Input identity), die privaten
# Schlüssel aus SOPS. Kein DNS in den Profilen: resolved behält das globale DoT
# (Quad9/Mullvad), die Anfragen laufen über die Default-Route durch den Tunnel.

{ config, lib, pkgs, id, vpnServer, ... }:

let
  slotName = s: "wg-${toString s.slot}";
  schluesselName = s: "wireguard/slot${toString s.slot}";
  envName = s: "WG${toString s.slot}_KEY";

  profil = s: lib.nameValuePair (slotName s) {
    connection = {
      id = slotName s;
      type = "wireguard";
      interface-name = slotName s;
      # Kein NM-Autoconnect: beim Boot verbindet vpn-boot.service Slot 1 genau einmal.
      autoconnect = false;
    };
    wireguard.private-key = "$" + envName s;
    "wireguard-peer.${s.serverPublicKey}" = {
      endpoint = "${s.endpoint}:${toString s.port}";
      allowed-ips = "0.0.0.0/0;";
      # Pflicht: ohne Verkehr handshaket WireGuard nicht, ein ruhender Tunnel sähe
      # sonst nach 180 s aus wie ein hängender.
      persistent-keepalive = 25;
    };
    ipv4 = {
      method = "manual";
      address1 = s.address;
    };
    ipv6.method = "disabled";
  };
in
{
  assertions = [
    {
      assertion = builtins.sort builtins.lessThan (map (s: s.slot) vpnServer) == lib.range 1 9;
      message = "vpn: Serverliste braucht genau die Slots 1–9 (identity/vpn/laptop.nix).";
    }
    {
      assertion = lib.all (s: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" s.endpoint != null) vpnServer;
      message = "vpn: endpoint muss eine IPv4-Adresse sein — die Firewall-Regel braucht IPs, keine Namen.";
    }
  ];

  boot.kernelModules = [ "wireguard" ];

  sops.secrets = lib.listToAttrs (map (s: lib.nameValuePair (schluesselName s) { }) vpnServer);

  sops.templates."nm-wireguard-env" = {
    content = lib.concatMapStrings
      (s: "${envName s}=${config.sops.placeholder.${schluesselName s}}\n")
      vpnServer;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."nm-wireguard-env".path ];
    profiles = lib.listToAttrs (map profil vpnServer);
  };

  # Namen für Leiste und Befehl — Slot und Anzeigename, nichts Geheimes.
  environment.etc."vpn/server.json".text =
    builtins.toJSON (map (s: { inherit (s) slot name; }) vpnServer);

  # Beim Boot einmal Slot 1 verbinden — sonst wären Dienste ohne Login
  # (Mail-Alarme, CVE-Monitor, Suricata-Updates) mit Kill-Switch ausgesperrt.
  systemd.services.vpn-boot = {
    description = "VPN: beim Boot mit Slot 1 verbinden";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    wants = [ "NetworkManager-ensure-profiles.service" ];
    # Ein nixos-rebuild soll einen laufenden Tunnel nicht umschalten.
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.networkmanager}/bin/nmcli connection up wg-1";
    };
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];
}
```

In `configuration.nix` unter `./modules/protonvpn.nix` die Zeile `./modules/vpn.nix` ergänzen.
`protonvpn.nix` lädt ebenfalls `wireguard`; doppelte Einträge in `boot.kernelModules` sind
unschädlich und verschwinden in Aufgabe 6.

- [ ] **Schritt 4: Grüner Test — Auswertung und Bau**

```bash
nix eval --json .#nixosConfigurations.nixos.config.networking.networkmanager.ensureProfiles.profiles --apply 'p: builtins.filter (n: builtins.match "wg-[1-9]" n != null) (builtins.attrNames p)'
nix eval --json .#nixosConfigurations.nixos.config.networking.networkmanager.ensureProfiles.profiles.wg-3 --apply 'p: { c = p.connection; ipv6 = p.ipv6; peerSektionen = builtins.length (builtins.filter (n: builtins.substring 0 15 n == "wireguard-peer.") (builtins.attrNames p)); dnsGesetzt = p.ipv4 ? dns; key = p.wireguard.private-key; }'
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
```
Erwartet: 9 Namen `wg-1`…`wg-9`; bei `wg-3` `autoconnect=false`, `interface-name="wg-3"`,
`ipv6.method="disabled"`, `peerSektionen=1`, `dnsGesetzt=false`, `key="$WG3_KEY"`; Bau ohne Fehler.

- [ ] **Schritt 5: Commit**

```bash
git add flake.nix flake.lock modules/vpn.nix configuration.nix
git commit -m "vpn: neun WireGuard-Profile aus privater Serverliste, Boot verbindet Slot 1"
```

- [ ] **Schritt 6: [Nutzer] Aktivieren**

```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
```

- [ ] **Schritt 7: Profile und Boot-Dienst am System messen**

```bash
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show | rg '^wg-'
systemctl is-active vpn-boot.service
nmcli -t -f NAME connection show --active | rg '^wg-'
```
Erwartet: 9 Zeilen `wg-<n>:wireguard:no`. `vpn-boot` wird durch `switch` gestartet
(neue Unit mit `wantedBy`) → `active`, `wg-1` aktiv.

- [ ] **Schritt 8: Tunnel trägt — Exit-IP durch `wg-1`**

```bash
curl --silent --show-error --fail --max-time 15 --interface wg-1 https://am.i.mullvad.net/json | jq '{country, city, organization, mullvad_exit_ip}'
curl --silent --show-error --fail --max-time 15 --interface wlp0s20f3 https://am.i.mullvad.net/json | jq '{country, organization}'
```
Erwartet: erste Abfrage liefert Land von Slot 1 und eine Proton-Organisation; zweite den
Heim-Anbieter. **IPs nicht in Plan oder Commit übernehmen.** Scheitert `--interface wg-1`:
`wg show wg-1` ansehen (Handshake?), dann `ip rule`/`ip route show table all | rg wg-1`.

- [ ] **Schritt 9: resolved nutzt am Tunnel kein eigenes DNS**

```bash
resolvectl status wg-1
resolvectl query am.i.mullvad.net
```
Erwartet: `wg-1` ohne `DNS Servers`, ohne `DNS Domain ~.`; die Abfrage klappt mit
`authenticated: yes` bzw. ohne DNSSEC-Fehler. Sonst: **Stopp**, Befund an den Nutzer — die
DNS-Entscheidung A der Spec wäre dann nicht erfüllt.

- [ ] **Schritt 10: rp_filter und `src_valid_mark` messen**

```bash
sysctl net.ipv4.conf.wg-1.rp_filter net.ipv4.conf.all.src_valid_mark
```
Erwartet laut Spec-Messung: `rp_filter = 2`. Da Schritt 8 schon Verkehr belegt, ist nichts zu
ändern. Nur falls Schritt 8 scheiterte und `rp_filter = 1` zeigt: Befund an den Nutzer.

- [ ] **Schritt 11: NetShield-Messung für die spätere DNS-Entscheidung**

Protons Resolver direkt durch den Tunnel befragen (ohne resolved; `dig` aus `nixpkgs#dig`):

```bash
nix shell --inputs-from . nixpkgs#dig -c bash -c '
  for d in dnssec-failed.org rusty-vault.de doubleclick.net; do
    echo "== $d";
    dig @10.2.0.1 +dnssec +time=5 +tries=1 "$d" A | rg "status:|flags:|^[a-z].*\sA\s" ;
  done'
nix shell --inputs-from . nixpkgs#dig -c dig @10.2.0.1 +dnssec +time=5 +tries=1 . DNSKEY | rg -c RRSIG
resolvectl query doubleclick.net
```
Festhalten (nur Befund, keine IPs):
- `dnssec-failed.org`: `SERVFAIL` = Proton validiert; `NOERROR` mit `ad`-Flag fehlt = validiert nicht.
- `rusty-vault.de`: löst auf oder nicht.
- `. DNSKEY` mit `RRSIG`-Zählung > 0 = Resolver reicht DNSSEC-Daten durch (Voraussetzung für
  strenges `DNSSEC=yes` in resolved).
- `doubleclick.net` über 10.2.0.1: `0.0.0.0`/`NXDOMAIN` = NetShield filtert.
- `doubleclick.net` über resolved (Quad9): **muss normal auflösen** — sonst filtert NetShield doch
  außerhalb von DNS, und die Konfigurationen sind ohne NetShield neu zu erzeugen.

Befund an den Nutzer mit Empfehlung. **Diese Aufgabe ändert DNS nicht.**

- [ ] **Schritt 12: Fortschrittstabelle aktualisieren und committen**

Zeile „2 Profile + Messungen“ mit Commit-Hash und den Befunden (ohne IPs/Servernamen) füllen.

```bash
git add docs/superpowers/plans/2026-09-13-wireguard-statt-proton-gui.md
git commit -m "Plan: Aufgabe 2 erledigt, Messbefunde"
```

---

## Aufgabe 3: Status-Dienst, Zustand „Direkt“, polkit

**Dateien:**
- Erstellen: `modules/vpn/vpn-status.sh`
- Ändern: `modules/vpn.nix` (let-Block + Dienste + polkit)
- Ändern: `modules/firewall.nix` (Chain `direkt`, `jump direkt` am Ende der Output-Chain)

**Interfaces:**
- Konsumiert: `/etc/vpn/server.json` (Aufgabe 2).
- Produziert: `/run/vpn/status.json` alle 2 s, genau diese Felder:
  `{ "zeit": int, "slot": int|null, "name": string|null, "handshake_alter": int|null, "rx": int|null, "tx": int|null, "direkt": bool, "killswitch": bool }`;
  `vpn-direkt.service` (start/stop/restart ohne Passwort für den Nutzer);
  nft-Chain `inet filter direkt` (leer = nicht direkt).

- [x] **Schritt 1: Roter Test**

```bash
systemctl cat vpn-status.service vpn-direkt.service 2>&1 | head -2
test -e /run/vpn/status.json && echo vorhanden || echo fehlt
```
Erwartet: `No files found for vpn-status.service.` und `fehlt`.

- [x] **Schritt 2: `modules/vpn/vpn-status.sh` anlegen**

Ohne Shebang und `set`-Zeilen — `writeShellApplication` setzt beides und prüft mit shellcheck.

```bash
# vpn-status — misst alle 2 s den VPN-Zustand und schreibt /run/vpn/status.json.
# Läuft als root: wg und nft brauchen CAP_NET_ADMIN. Leser: Leiste und `vpn status`.
#
# Gemessen wird am Kernel (wg, nft), nicht an NetworkManager: Ein aktives Profil
# ohne Handshake soll als solches sichtbar sein, nicht als "verbunden".
# Achtung pipefail: `… | grep -q` kann den Schreiber per SIGPIPE beenden und die
# Pipeline dann als Fehlschlag melden. Deshalb erst in Variablen lesen.

server_json=/etc/vpn/server.json
ziel=/run/vpn/status.json

while true; do
  jetzt=$(date +%s)
  slot=null
  name=null
  alter=null
  rx=null
  tx=null

  iface=$(wg show interfaces | tr ' ' '\n' | grep -E '^wg-[1-9]$' | head -n 1 || true)
  if [ -n "$iface" ]; then
    slot=${iface#wg-}
    name=$(jq -c --argjson s "$slot" '[.[] | select(.slot == $s) | .name][0]' "$server_json")

    hs=$(wg show "$iface" latest-handshakes | awk 'NR == 1 { print $2 }')
    if [ -n "$hs" ] && [ "$hs" -gt 0 ]; then
      alter=$((jetzt - hs))
    fi

    transfer=$(wg show "$iface" transfer | awk 'NR == 1 { print $2, $3 }')
    if [ -n "$transfer" ]; then
      rx=${transfer% *}
      tx=${transfer#* }
    fi
  fi

  # Wahrheit für "Direkt" ist die Chain, nicht der Unit-Zustand: ein nftables-Reload
  # leert die Chain, die Unit bliebe "active".
  kette_direkt=$(nft list chain inet filter direkt 2>/dev/null || true)
  direkt=false
  if grep -qw accept <<<"$kette_direkt"; then
    direkt=true
  fi

  kette_output=$(nft list chain inet filter output 2>/dev/null || true)
  killswitch=false
  if grep -q 'policy drop' <<<"$kette_output"; then
    killswitch=true
  fi

  jq -n \
    --argjson zeit "$jetzt" --argjson slot "$slot" --argjson name "$name" \
    --argjson handshake_alter "$alter" --argjson rx "$rx" --argjson tx "$tx" \
    --argjson direkt "$direkt" --argjson killswitch "$killswitch" \
    '{zeit: $zeit, slot: $slot, name: $name, handshake_alter: $handshake_alter,
      rx: $rx, tx: $tx, direkt: $direkt, killswitch: $killswitch}' \
    > "$ziel.tmp"
  mv "$ziel.tmp" "$ziel"

  sleep 2
done
```

- [x] **Schritt 3: `modules/vpn.nix` erweitern**

Im `let`-Block nach `profil = …;` ergänzen:

```nix
  vpnStatus = pkgs.writeShellApplication {
    name = "vpn-status";
    runtimeInputs = with pkgs; [ wireguard-tools nftables jq gnugrep gawk coreutils ];
    text = builtins.readFile ./vpn/vpn-status.sh;
  };

  # Füllt die Chain `direkt` (firewall.nix). Fremdes DoT/DoQ bleibt auch ungeschützt
  # gesperrt; erlaubt sind nur die resolved-Server Quad9 und Mullvad.
  direktAn = pkgs.writeShellScript "vpn-direkt-an" ''
    ${pkgs.nftables}/bin/nft -f - <<'EOF'
    flush chain inet filter direkt
    add rule inet filter direkt meta l4proto { tcp, udp } th dport 853 ip daddr != { 9.9.9.9, 194.242.2.2 } drop
    add rule inet filter direkt accept
    EOF
  '';
```

Im Attrset nach `systemd.services.vpn-boot = { … };` ergänzen:

```nix
  systemd.services.vpn-status = {
    description = "VPN: Zustand messen und nach /run/vpn/status.json schreiben";
    wantedBy = [ "multi-user.target" ];
    after = [ "nftables.service" ];
    serviceConfig = {
      ExecStart = "${vpnStatus}/bin/vpn-status";
      Restart = "always";
      RestartSec = "2s";
      RuntimeDirectory = "vpn";
      RuntimeDirectoryMode = "0755";
      UMask = "0022";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  # Zustand "Direkt": Kill-Switch bewusst aus, z. B. für Captive Portals.
  # Kein wantedBy → nach einem Neustart nie aktiv. Ein nftables-Reload leert die
  # Chain ohnehin; `vpn direkt` benutzt deshalb restart, nicht start.
  systemd.services.vpn-direkt = {
    description = "VPN: Kill-Switch bewusst aus (Zustand Direkt)";
    after = [ "nftables.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = direktAn;
      ExecStop = "${pkgs.nftables}/bin/nft flush chain inet filter direkt";
    };
  };

  # Der Nutzer darf genau vpn-direkt.service starten, stoppen, neu starten — nur in
  # der aktiven lokalen Sitzung und ohne Passwort. Sonst nichts an systemd.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "vpn-direkt.service" &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
          subject.user == "${id.username}" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
```

- [x] **Schritt 4: Chain `direkt` in `modules/firewall.nix`**

In der Output-Chain als **letzte** Regel, direkt vor `# 19. Dropped packets (logging temporarily disabled)`:

```nft
          # 18b. Zustand "Direkt" (vpn-direkt.service füllt die Chain, sonst leer).
          #      Unter policy accept wirkungslos; ab dem Kill-Switch die einzige
          #      Freigabe für ungeschützten Verkehr.
          jump direkt
```

Nach der schließenden Klammer der `forward`-Chain, noch innerhalb von `table inet filter`:

```nft
        # Zustand "Direkt" — leer, bis vpn-direkt.service sie füllt.
        chain direkt {
        }
```

- [x] **Schritt 5: Bau (shellcheck + nft-Syntaxprüfung laufen mit)**

```bash
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
```
Erwartet: ohne Fehler. Meldet shellcheck etwas: am Skript beheben, nicht abschalten.

- [x] **Schritt 6: Commit**

```bash
git add modules/vpn.nix modules/vpn/vpn-status.sh modules/firewall.nix
git commit -m "vpn: Status-Dienst, Zustand Direkt als nft-Chain, polkit nur für vpn-direkt"
```

- [x] **Schritt 7: [Nutzer] Aktivieren**

```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
```

- [x] **Schritt 8: Statusdatei messen**

```bash
stat -c '%a %U' /run/vpn/status.json
jq -c . /run/vpn/status.json; sleep 3; jq -c . /run/vpn/status.json
```
Erwartet: `644 root`; `slot` 1, `name` von Slot 1, `handshake_alter` < 180, `rx`/`tx` Zahlen,
`direkt` false, `killswitch` false; `zeit` steigt zwischen den Abfragen.

- [x] **Schritt 9: Tunnel weg → `slot` null**

```bash
nmcli connection down wg-1; sleep 3; jq -c '{slot, handshake_alter}' /run/vpn/status.json
nmcli connection up wg-1; sleep 4; jq -c '{slot, handshake_alter}' /run/vpn/status.json
```
Erwartet: erst `{"slot":null,"handshake_alter":null}`, dann Slot 1 mit kleinem Alter.

- [x] **Schritt 10: „Direkt“ ohne Passwort, Wahrheit aus der Chain**

```bash
systemctl start vpn-direkt.service; sleep 3; jq .direkt /run/vpn/status.json
systemctl stop vpn-direkt.service; sleep 3; jq .direkt /run/vpn/status.json
```
Erwartet: keine Passwortabfrage, erst `true`, dann `false`. Fragt polkit trotzdem (Tool-Bash
nicht in der aktiven Sitzung): dieselben Befehle **[Nutzer]** in GNOME Console.

- [x] **Schritt 11: [Nutzer] nftables-Reload beendet „Direkt“**

```nu
systemctl start vpn-direkt.service
sudo systemctl restart nftables.service
```
Danach im Tool-Bash:
```bash
sleep 3; jq .direkt /run/vpn/status.json; systemctl is-active vpn-direkt.service
systemctl stop vpn-direkt.service
```
Erwartet: `false` (Chain geleert) obwohl die Unit `active` meldet — genau der Grund für
Verfeinerung 2. Danach Unit gestoppt.

- [x] **Schritt 12: Fortschritt eintragen, committen**

---

## Aufgabe 4: Der Befehl `vpn`

**Dateien:**
- Erstellen: `modules/vpn/vpn.sh`
- Ändern: `modules/vpn.nix` (let-Block + `environment.systemPackages`)

**Interfaces:**
- Konsumiert: `/etc/vpn/server.json`, `/run/vpn/status.json`, `vpn-direkt.service`, Profile `wg-<n>`.
- Produziert: `/run/current-system/sw/bin/vpn` mit
  `vpn 1…9 | aus | direkt | login | status`; Exit-Codes 0 = Wirkung belegt, 1 = Tunnel trägt
  nicht / NM-Fehler, 2 = Aufruffehler, 3 = andere Umschaltung läuft;
  `$XDG_RUNTIME_DIR/vpn/exit.json` = `{ "slot": int, "ip": string, "zeit": int }`;
  `${XDG_STATE_HOME:-~/.local/state}/vpn/letzter` = eine Ziffer 1–9.

- [x] **Schritt 1: Roter Test**

```bash
command -v vpn || echo fehlt
```
Erwartet: `fehlt`.

- [x] **Schritt 2: `modules/vpn/vpn.sh` anlegen**

```bash
# vpn — einziger Umschaltpfad für die WireGuard-Slots (Tastenkürzel, Leiste, Terminal).
#
#   vpn 1…9      mit Slot n verbinden, andere Tunnel trennen, Wirkung prüfen
#   vpn aus      alle Tunnel trennen, "Direkt" beenden
#   vpn direkt   alle Tunnel trennen, Kill-Switch bewusst aus (Captive Portal)
#   vpn login    nach dem Login auf den zuletzt benutzten Slot wechseln
#   vpn status   gemessenen Zustand ausgeben
#
# Erfolg heißt: Die Exit-IP kam durch den Tunnel zurück. nmcli meldet bei WireGuard
# auch ohne Handshake Erfolg — das allein zählt nicht.
# Exit-Codes: 0 belegt, 1 Tunnel trägt nicht, 2 Aufruffehler, 3 Umschaltung läuft.

server_json=/etc/vpn/server.json
status_json=/run/vpn/status.json
exit_url=https://am.i.mullvad.net/json
laufzeit="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR fehlt}/vpn"
zustand="${XDG_STATE_HOME:-$HOME/.local/state}/vpn"

melde() {
  # $1 Dringlichkeit (low|normal|critical), $2 Titel, $3 Text
  printf '%s: %s\n' "$2" "$3" >&2
  notify-send --app-name=VPN --urgency="$1" "$2" "$3" 2>/dev/null || true
}

sperre() {
  mkdir -p "$laufzeit"
  exec 9>"$laufzeit/lock"
  if ! flock -n 9; then
    melde normal "VPN" "Umschaltung läuft bereits."
    exit 3
  fi
}

aktive_tunnel() {
  nmcli -t -f NAME,TYPE connection show --active \
    | awk -F: '$2 == "wireguard" && $1 ~ /^wg-[1-9]$/ { print $1 }'
}

trenne_tunnel_ausser() {
  local behalten=${1:-} verbindung
  while read -r verbindung; do
    if [ -n "$verbindung" ] && [ "$verbindung" != "$behalten" ]; then
      nmcli connection down "$verbindung" >/dev/null
    fi
  done < <(aktive_tunnel)
}

name_von() {
  jq -r --argjson s "$1" '[.[] | select(.slot == $s) | .name][0] // empty' "$server_json"
}

schreibe_exit() {
  # $1 Slot, $2 IP — atomar, damit die Leiste nie eine halbe Datei liest
  jq -n --argjson slot "$1" --arg ip "$2" --argjson zeit "$(date +%s)" \
    '{slot: $slot, ip: $ip, zeit: $zeit}' > "$laufzeit/exit.json.tmp"
  mv "$laufzeit/exit.json.tmp" "$laufzeit/exit.json"
}

verbinde() {
  local slot=$1 name verbindung antwort ip land
  name=$(name_von "$slot")
  if [ -z "$name" ]; then
    echo "vpn: Slot $slot gibt es nicht" >&2
    exit 2
  fi
  verbindung="wg-$slot"

  trenne_tunnel_ausser "$verbindung"
  rm -f "$laufzeit/exit.json"

  if ! nmcli connection up "$verbindung" >/dev/null; then
    melde critical "⚠ VPN $name" "NetworkManager konnte $verbindung nicht aktivieren."
    exit 1
  fi

  if antwort=$(curl --silent --fail --max-time 15 --interface "$verbindung" "$exit_url") \
    && ip=$(jq -er '.ip' <<<"$antwort"); then
    land=$(jq -r '.country // "?"' <<<"$antwort")
    schreibe_exit "$slot" "$ip"
    mkdir -p "$zustand"
    echo "$slot" > "$zustand/letzter"
    # Erst nach bestätigtem Tunnel: Scheitert er, bleibt "Direkt" bestehen.
    if ! systemctl stop vpn-direkt.service; then
      melde critical "⚠ VPN $name" "Tunnel steht, aber vpn-direkt ließ sich nicht stoppen."
      exit 1
    fi
    melde normal "🔒 VPN $name" "Exit $ip ($land)"
  else
    melde critical "⚠ VPN $name" "Kein Verkehr durch den Tunnel (Exit-IP nicht abrufbar). Das Profil bleibt aktiv, WireGuard versucht es weiter."
    exit 1
  fi
}

aus() {
  trenne_tunnel_ausser ""
  rm -f "$laufzeit/exit.json"
  systemctl stop vpn-direkt.service
  melde normal "⛔ VPN aus" "Alle Tunnel getrennt."
}

direkt() {
  trenne_tunnel_ausser ""
  rm -f "$laufzeit/exit.json"
  # restart statt start: Nach einem nftables-Reload ist die Unit evtl. noch
  # "active", die Chain aber leer — start wäre dann wirkungslos.
  systemctl restart vpn-direkt.service
  melde critical "⚠ VPN DIREKT" "Kill-Switch aus, Verkehr ungeschützt — bis ein Server gewählt wird oder bis zum Neustart."
}

login() {
  local slot=1
  if [ -r "$zustand/letzter" ]; then
    slot=$(cat "$zustand/letzter")
  fi
  case "$slot" in
    [1-9]) ;;
    *) slot=1 ;;
  esac
  if [ "$(aktive_tunnel)" = "wg-$slot" ]; then
    exit 0
  fi
  verbinde "$slot"
}

zeige_status() {
  jq . "$status_json"
  if [ -r "$laufzeit/exit.json" ]; then
    jq . "$laufzeit/exit.json"
  fi
}

case "${1:-}" in
  [1-9]) sperre; verbinde "$1" ;;
  aus) sperre; aus ;;
  direkt) sperre; direkt ;;
  login) sperre; login ;;
  status) zeige_status ;;
  *)
    echo "Aufruf: vpn 1…9 | aus | direkt | login | status" >&2
    exit 2
    ;;
esac
```

- [x] **Schritt 3: In `modules/vpn.nix` einbinden**

Im `let`-Block nach `direktAn`:

```nix
  vpnBefehl = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ networkmanager jq curl util-linux libnotify systemd coreutils gawk ];
    text = builtins.readFile ./vpn/vpn.sh;
  };
```

`environment.systemPackages = [ pkgs.wireguard-tools vpnBefehl ];`

- [x] **Schritt 4: Bau und Aufruftests ohne Netz**

Der Bau des Systems baut das Paket mit; danach seinen Pfad aus der Konfiguration holen:

```bash
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
v=$(nix eval --raw .#nixosConfigurations.nixos.config.environment.systemPackages --apply 'ps: toString (builtins.head (builtins.filter (p: (p.name or "") == "vpn") ps))')
"$v/bin/vpn"; echo "exit=$?"
"$v/bin/vpn" 0; echo "exit=$?"
"$v/bin/vpn" status | jq -c '{slot, killswitch}'
```
Erwartet: Bau ohne shellcheck-Fehler; zweimal Aufrufzeile mit `exit=2`; Status als JSON.

- [x] **Schritt 5: Commit**

```bash
git add modules/vpn.nix modules/vpn/vpn.sh
git commit -m "vpn: Befehl vpn — Slot wählen mit Exit-IP-Prüfung, aus, direkt, login, status"
```

- [x] **Schritt 6: [Nutzer] Aktivieren**

```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
```

- [x] **Schritt 7: Alle neun Slots — Wirkung messen (keine IPs notieren)**

```bash
for n in 1 2 3 4 5 6 7 8 9; do
  if vpn "$n" 2>/dev/null; then
    printf 'Slot %s: aktiv=%s land=%s\n' "$n" \
      "$(nmcli -t -f NAME connection show --active | rg '^wg-' | tr '\n' ' ')" \
      "$(curl -s --max-time 15 https://am.i.mullvad.net/json | jq -r .country)"
  else
    echo "Slot $n: FEHLER exit=$?"
  fi
done
cat "${XDG_STATE_HOME:-$HOME/.local/state}/vpn/letzter"; jq -c '{slot}' "$XDG_RUNTIME_DIR/vpn/exit.json"
```
Erwartet: je Slot genau ein aktives Profil `wg-<n>`, das Land passt zum Servernamen (Kürzel im
Namen), `letzter` = 9, `exit.json` Slot 9. Die zweite Abfrage läuft **ohne** `--interface` —
sie belegt, dass auch normaler Verkehr durch den Tunnel geht.

- [x] **Schritt 8: Sperre gegen parallele Umschaltung**

```bash
vpn 2 & sleep 0.5; vpn 3; echo "exit=$?"; wait
nmcli -t -f NAME connection show --active | rg '^wg-'
```
Erwartet: `exit=3`, danach nur `wg-2` aktiv.

- [x] **Schritt 9: `aus`, `direkt`, Rückkehr aus `direkt`, `login`**

```bash
vpn aus; sleep 3; jq -c '{slot, direkt}' /run/vpn/status.json; test -e "$XDG_RUNTIME_DIR/vpn/exit.json" && echo exit-da || echo exit-weg
vpn direkt; sleep 3; jq -c '{slot, direkt}' /run/vpn/status.json
vpn 4; sleep 3; jq -c '{slot, direkt}' /run/vpn/status.json
echo 6 > "${XDG_STATE_HOME:-$HOME/.local/state}/vpn/letzter"; vpn login; jq -c '{slot}' "$XDG_RUNTIME_DIR/vpn/exit.json"
vpn login; echo "zweites login exit=$?"
```
Erwartet: `{"slot":null,"direkt":false}` + `exit-weg`; `{"slot":null,"direkt":true}`;
`{"slot":4,"direkt":false}`; Slot 6; `zweites login exit=0` ohne neue Umschaltung.
Fragt polkit im Tool-Bash nach einem Passwort: Schritt 9 **[Nutzer]** in GNOME Console.

- [x] **Schritt 10: Nutzer wählt seinen Alltags-Slot** (`vpn <n>`), Fortschritt eintragen, committen.

---

## Aufgabe 5: Leisten-Erweiterung, Tastenkürzel, Wechsel beim Login

**Dateien:**
- Erstellen: `modules/home/vpn-indikator/test-zustand.js`, `zustand.js`, `extension.js`,
  `metadata.json`, `stylesheet.css`
- Erstellen: `modules/home/vpn.nix`
- Ändern: `home.nix:27-32` (Import `./modules/home/vpn.nix`)

**Interfaces:**
- Konsumiert: `/run/vpn/status.json` (Felder aus Aufgabe 3), `$XDG_RUNTIME_DIR/vpn/exit.json`
  und `/run/current-system/sw/bin/vpn` (Aufgabe 4), `/etc/vpn/server.json` (Aufgabe 2).
- Produziert: `berechneZustand(status, exit, jetzt) → { art, text, exitIp }` mit
  `art ∈ { "unbekannt", "direkt", "gesperrt", "offen", "haengt", "verbunden" }`;
  Erweiterung `vpn-indikator@local`; dconf-Kürzel `vpn0`…`vpn9`; User-Unit `vpn-login`.

- [ ] **Schritt 1: Test der Zustandslogik schreiben — `modules/home/vpn-indikator/test-zustand.js`**

```js
// Test der Zustandslogik. Läuft mit `gjs -m` — ohne GNOME Shell, beim Bau des Pakets.
import System from 'system';
import {berechneZustand} from './zustand.js';

let fehler = 0;
function pruefe(beschreibung, ist, soll) {
    const a = JSON.stringify(ist);
    const b = JSON.stringify(soll);
    if (a === b) {
        print(`ok      ${beschreibung}`);
    } else {
        printerr(`FEHLER  ${beschreibung}: ist ${a}, soll ${b}`);
        fehler++;
    }
}

const jetzt = 1000;
const basis = {
    zeit: 998, slot: 2, name: 'XX-2', handshake_alter: 30,
    rx: 1, tx: 1, direkt: false, killswitch: true,
};
const exit2 = {slot: 2, ip: '192.0.2.1', zeit: 990};

pruefe('kein Status → unbekannt',
    berechneZustand(null, null, jetzt),
    {art: 'unbekannt', text: '? VPN', exitIp: null});
pruefe('Status 16 s alt → unbekannt',
    berechneZustand({...basis, zeit: 984}, exit2, jetzt),
    {art: 'unbekannt', text: '? VPN', exitIp: null});
pruefe('Status genau 15 s alt → noch gültig',
    berechneZustand({...basis, zeit: 985}, exit2, jetzt).art,
    'verbunden');
pruefe('direkt geht vor Tunnel',
    berechneZustand({...basis, direkt: true}, exit2, jetzt),
    {art: 'direkt', text: '⚠ DIREKT', exitIp: null});
pruefe('kein Tunnel, Kill-Switch an → gesperrt',
    berechneZustand({...basis, slot: null, name: null, handshake_alter: null}, null, jetzt),
    {art: 'gesperrt', text: '⛔ gesperrt', exitIp: null});
pruefe('kein Tunnel, Kill-Switch aus → offen',
    berechneZustand({...basis, slot: null, name: null, handshake_alter: null, killswitch: false}, null, jetzt),
    {art: 'offen', text: '⚠ OFFEN', exitIp: null});
pruefe('verbunden mit passender Exit-IP',
    berechneZustand(basis, exit2, jetzt),
    {art: 'verbunden', text: '🔒 XX-2', exitIp: '192.0.2.1'});
pruefe('Exit-IP eines anderen Slots wird nicht gezeigt',
    berechneZustand(basis, {...exit2, slot: 5}, jetzt),
    {art: 'verbunden', text: '🔒 XX-2', exitIp: null});
pruefe('nie Handshake → hängt',
    berechneZustand({...basis, handshake_alter: null}, exit2, jetzt),
    {art: 'haengt', text: '⚠ XX-2', exitIp: '192.0.2.1'});
pruefe('Handshake genau 180 s → hängt',
    berechneZustand({...basis, handshake_alter: 180}, exit2, jetzt).art,
    'haengt');
pruefe('Handshake 179 s → verbunden',
    berechneZustand({...basis, handshake_alter: 179}, exit2, jetzt).art,
    'verbunden');
pruefe('fehlender Name → Interfacename',
    berechneZustand({...basis, name: null}, null, jetzt).text,
    '🔒 wg-2');

System.exit(fehler === 0 ? 0 : 1);
```

- [ ] **Schritt 2: Test laufen lassen — muss scheitern**

```bash
nix shell --inputs-from . nixpkgs#gjs -c gjs -m modules/home/vpn-indikator/test-zustand.js; echo "exit=$?"
```
Erwartet: Fehler beim Import von `./zustand.js` (Datei fehlt), `exit=` ungleich 0.

- [ ] **Schritt 3: `modules/home/vpn-indikator/zustand.js`**

```js
// Reine Zustandslogik der VPN-Anzeige — ohne GNOME-Importe, damit sie mit gjs testbar ist.
// Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md

// WireGuard verhandelt bei Verkehr spätestens alle 120 s neu (Keepalive 25 s sorgt für Verkehr).
export const HANDSHAKE_GRENZE_S = 180;
// Der Status-Dienst schreibt alle 2 s; älter als das heißt: er läuft nicht.
export const STATUS_GRENZE_S = 15;

export function berechneZustand(status, exit, jetzt) {
    if (!status || typeof status.zeit !== 'number' || jetzt - status.zeit > STATUS_GRENZE_S)
        return {art: 'unbekannt', text: '? VPN', exitIp: null};

    if (status.direkt)
        return {art: 'direkt', text: '⚠ DIREKT', exitIp: null};

    if (status.slot === null) {
        // Ohne Kill-Switch ist "kein Tunnel" nicht gesperrt, sondern offen.
        return status.killswitch
            ? {art: 'gesperrt', text: '⛔ gesperrt', exitIp: null}
            : {art: 'offen', text: '⚠ OFFEN', exitIp: null};
    }

    const name = status.name ?? `wg-${status.slot}`;
    const exitIp = exit && exit.slot === status.slot ? exit.ip : null;

    if (status.handshake_alter === null || status.handshake_alter >= HANDSHAKE_GRENZE_S)
        return {art: 'haengt', text: `⚠ ${name}`, exitIp};

    return {art: 'verbunden', text: `🔒 ${name}`, exitIp};
}
```

- [ ] **Schritt 4: Test laufen lassen — muss bestehen**

```bash
nix shell --inputs-from . nixpkgs#gjs -c gjs -m modules/home/vpn-indikator/test-zustand.js; echo "exit=$?"
```
Erwartet: 12 Zeilen `ok`, `exit=0`.

- [ ] **Schritt 5: `modules/home/vpn-indikator/metadata.json`**

```json
{
  "uuid": "vpn-indikator@local",
  "name": "VPN-Indikator",
  "description": "Gemessener WireGuard-Zustand in der Leiste; umgeschaltet wird über den Befehl vpn.",
  "shell-version": ["50"],
  "session-modes": ["user"],
  "version": 1
}
```

- [ ] **Schritt 6: `modules/home/vpn-indikator/stylesheet.css`**

```css
.vpn-indikator { font-weight: bold; }
.vpn-verbunden { color: #8ff0a4; }
.vpn-haengt { color: #ffbe6f; }
.vpn-gesperrt,
.vpn-unbekannt { color: #9a9996; }
.vpn-direkt,
.vpn-offen { color: #ff7b63; }
```

- [ ] **Schritt 7: `modules/home/vpn-indikator/extension.js`**

```js
// VPN-Indikator: zeigt den gemessenen WireGuard-Zustand in der Leiste.
// Liest nur Dateien (Status-Dienst, `vpn`, Serverliste) und schaltet nur über `vpn`.
// Fällt die Erweiterung aus, fehlt nur die Anzeige — Kill-Switch und Kürzel sind unabhängig.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Dialog from 'resource:///org/gnome/shell/ui/dialog.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ModalDialog from 'resource:///org/gnome/shell/ui/modalDialog.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {berechneZustand} from './zustand.js';

const STATUS_DATEI = '/run/vpn/status.json';
const SERVER_DATEI = '/etc/vpn/server.json';
const VPN_BEFEHL = '/run/current-system/sw/bin/vpn';

function leseJson(pfad) {
    try {
        const [ok, inhalt] = GLib.file_get_contents(pfad);
        return ok ? JSON.parse(new TextDecoder().decode(inhalt)) : null;
    } catch (e) {
        return null;
    }
}

function vpn(argument) {
    try {
        const prozess = Gio.Subprocess.new([VPN_BEFEHL, argument], Gio.SubprocessFlags.NONE);
        prozess.wait_async(null, (p, ergebnis) => p.wait_finish(ergebnis));
    } catch (e) {
        Main.notifyError('VPN', `„vpn ${argument}“ ließ sich nicht starten: ${e.message}`);
    }
}

function mib(bytes) {
    return `${(bytes / 1048576).toFixed(1)} MiB`;
}

const VpnIndikator = GObject.registerClass(
class VpnIndikator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'VPN-Indikator');

        this._label = new St.Label({
            text: '? VPN',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'vpn-indikator vpn-unbekannt',
        });
        this.add_child(this._label);

        this._zeileZustand = this._infoZeile();
        this._zeileHandshake = this._infoZeile();
        this._zeileExit = this._infoZeile();
        this._zeileTransfer = this._infoZeile();
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._serverEintraege = new Map();
        for (const {slot, name} of leseJson(SERVER_DATEI) ?? []) {
            const eintrag = new PopupMenu.PopupMenuItem(`${slot}  ${name}`);
            eintrag.connect('activate', () => vpn(String(slot)));
            this.menu.addMenuItem(eintrag);
            this._serverEintraege.set(slot, eintrag);
        }

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const aus = new PopupMenu.PopupMenuItem('0  Aus');
        aus.connect('activate', () => vpn('aus'));
        this.menu.addMenuItem(aus);
        const direkt = new PopupMenu.PopupMenuItem('⚠ Direkt (ungeschützt) …');
        direkt.connect('activate', () => this._bestaetigeDirekt());
        this.menu.addMenuItem(direkt);

        this._aktualisiere();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._aktualisiere();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _infoZeile() {
        const zeile = new PopupMenu.PopupMenuItem('', {reactive: false});
        this.menu.addMenuItem(zeile);
        return zeile;
    }

    _aktualisiere() {
        const status = leseJson(STATUS_DATEI);
        const exit = leseJson(GLib.build_filenamev([GLib.get_user_runtime_dir(), 'vpn', 'exit.json']));
        const z = berechneZustand(status, exit, Math.floor(Date.now() / 1000));

        this._label.text = z.text;
        this._label.style_class = `vpn-indikator vpn-${z.art}`;

        const tunnel = z.art === 'verbunden' || z.art === 'haengt';
        this._zeileZustand.label.text = {
            unbekannt: 'Status-Dienst liefert nichts (älter als 15 s)',
            direkt: 'Direkt — Kill-Switch aus, ungeschützt',
            gesperrt: 'Kein Tunnel — Verkehr gesperrt',
            offen: 'Kein Tunnel — Kill-Switch aus, Verkehr ungeschützt',
            haengt: 'Tunnel aktiv, aber kein frischer Handshake',
            verbunden: 'Verbunden',
        }[z.art];
        this._zeileHandshake.label.text = tunnel
            ? (status.handshake_alter === null ? 'Handshake: nie' : `Handshake vor ${status.handshake_alter} s`)
            : '';
        this._zeileExit.label.text = tunnel ? `Exit: ${z.exitIp ?? 'nicht bestätigt'}` : '';
        this._zeileTransfer.label.text = tunnel && status.rx !== null
            ? `↓ ${mib(status.rx)}   ↑ ${mib(status.tx)}`
            : '';
        for (const zeile of [this._zeileHandshake, this._zeileExit, this._zeileTransfer])
            zeile.visible = zeile.label.text !== '';

        const aktiv = z.art === 'unbekannt' ? null : status.slot;
        for (const [slot, eintrag] of this._serverEintraege) {
            eintrag.setOrnament(slot === aktiv
                ? PopupMenu.Ornament.CHECK
                : PopupMenu.Ornament.NONE);
        }
    }

    _bestaetigeDirekt() {
        const dialog = new ModalDialog.ModalDialog({destroyOnClose: true});
        dialog.contentLayout.add_child(new Dialog.MessageDialogContent({
            title: 'Ungeschützt ins Netz?',
            description: 'Alle Tunnel werden getrennt und der Kill-Switch abgeschaltet — bis du einen ' +
                'Server wählst oder neu startest. Gedacht für die Anmeldung an Captive Portals.',
        }));
        dialog.setButtons([
            {label: 'Abbrechen', action: () => dialog.close(), key: Clutter.KEY_Escape, default: true},
            {label: 'Direkt verbinden', action: () => { dialog.close(); vpn('direkt'); }},
        ]);
        dialog.open();
    }

    destroy() {
        if (this._timer) {
            GLib.Source.remove(this._timer);
            this._timer = null;
        }
        super.destroy();
    }
});

export default class VpnIndikatorExtension extends Extension {
    enable() {
        this._indikator = new VpnIndikator();
        Main.panel.addToStatusArea(this.uuid, this._indikator);
    }

    disable() {
        this._indikator?.destroy();
        this._indikator = null;
    }
}
```

- [ ] **Schritt 8: `modules/home/vpn.nix`**

```nix
# VPN in der GNOME-Sitzung: Leisten-Erweiterung, Tastenkürzel, Wechsel beim Login.
# Umgeschaltet wird immer über `vpn` (modules/vpn.nix).

{ lib, pkgs, ... }:

let
  uuid = "vpn-indikator@local";

  # Die Zustandslogik wird beim Bau getestet: ein roter Test macht den Bau rot.
  vpnIndikator = pkgs.runCommand "gnome-shell-extension-vpn-indikator"
    { nativeBuildInputs = [ pkgs.gjs ]; }
    ''
      export HOME=$TMPDIR
      gjs -m ${./vpn-indikator}/test-zustand.js
      ziel=$out/share/gnome-shell/extensions/${uuid}
      mkdir -p $ziel
      cp ${./vpn-indikator}/{metadata.json,extension.js,zustand.js,stylesheet.css} $ziel/
    '';

  ziffern = lib.range 0 9;
  pfad = n: "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vpn${toString n}/";
in
{
  home.packages = [ vpnIndikator ];

  # Listen in dconf.settings werden über Module hinweg zusammengeführt
  # (gemessen 2026-09-13 an enabled-extensions aus home.nix + gnome-settings.nix).
  dconf.settings = {
    "org/gnome/shell".enabled-extensions = [ uuid ];
    "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = map pfad ziffern;
  } // lib.listToAttrs (map
    (n: lib.nameValuePair "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vpn${toString n}" {
      name = if n == 0 then "VPN aus" else "VPN Slot ${toString n}";
      command = "/run/current-system/sw/bin/vpn ${if n == 0 then "aus" else toString n}";
      binding = "<Super><Alt>${toString n}";
    })
    ziffern);

  # Nach dem Login auf den zuletzt benutzten Slot (beim Boot verbindet vpn-boot Slot 1).
  systemd.user.services.vpn-login = {
    Unit = {
      Description = "VPN: nach dem Login auf den zuletzt benutzten Slot wechseln";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/vpn login";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
```

In `home.nix` in `imports` die Zeile `./modules/home/vpn.nix` ergänzen.

- [ ] **Schritt 9: Auswertung und Bau (der Bau führt den Test aus)**

```bash
nix eval --json .#nixosConfigurations.nixos.config.home-manager.users --apply 'u: builtins.mapAttrs (n: v: { ext = v.dconf.settings."org/gnome/shell".enabled-extensions; keys = v.dconf.settings."org/gnome/settings-daemon/plugins/media-keys".custom-keybindings; vpn3 = v.dconf.settings."org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vpn3"; }) u'
nix build --no-link -L .#nixosConfigurations.nixos.config.system.build.toplevel 2>&1 | rg 'ok      |FEHLER' ; echo "bau=${PIPESTATUS[0]}"
```
Erwartet: `ext` enthält `vpn-indikator@local` neben den vier bisherigen; `keys` die drei
bisherigen plus `vpn0`…`vpn9`; `vpn3` mit `binding "<Super><Alt>3"`, `command "…/vpn 3"`;
12 `ok`-Zeilen, `bau=0`. (Ist das Paket schon gebaut, fehlen die `ok`-Zeilen — dann zählt `bau=0`.)

- [ ] **Schritt 10: [Nutzer] Kollisionen der Kürzel prüfen — vor dem Aktivieren**

```nu
gsettings list-recursively | lines | where $it =~ '(?i)<super><alt>|<alt><super>'
```
Erwartet: leer. Sonst: Befund melden, Kürzel nicht aktivieren.

- [ ] **Schritt 11: Commit**

```bash
git add modules/home/vpn.nix modules/home/vpn-indikator home.nix
git commit -m "vpn: Leisten-Erweiterung mit getesteter Zustandslogik, Super+Alt+0…9, Login-Wechsel"
```

- [ ] **Schritt 12: [Nutzer] Aktivieren, dann ab- und wieder anmelden**

```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
```
Unter Wayland lädt GNOME neue Erweiterungen erst nach einer neuen Anmeldung.

- [ ] **Schritt 13: [Nutzer] Erweiterung und Login-Wechsel messen**

```nu
gnome-extensions info vpn-indikator@local
journalctl --user -b -o cat | lines | where $it =~ 'vpn-indikator|VpnIndikator'
systemctl --user status vpn-login --no-pager
```
Erwartet: `State: ACTIVE`; keine JS-Fehler; `vpn-login` mit `status=0/SUCCESS`, und die Leiste
zeigt den gemerkten Slot.

- [ ] **Schritt 14: [Nutzer] Sichtprüfung der Zustände**

| Handlung | Erwartung in der Leiste (≤ 3 s) |
|---|---|
| `Super+Alt+3` | `🔒 <Name Slot 3>` grün; Menü: Haken bei 3, Handshake, Exit-IP, ↓↑ |
| `Super+Alt+0` | `⚠ OFFEN` rot (Stufe 1, noch kein Kill-Switch) |
| Menü → „⚠ Direkt …“ → Abbrechen | nichts ändert sich |
| Menü → „⚠ Direkt …“ → Direkt verbinden | `⚠ DIREKT` rot |
| Menü → Slot 5 | `🔒 <Name Slot 5>` |
| `sudo systemctl stop vpn-status` | nach ≤ 15 s `? VPN` grau |
| `sudo systemctl start vpn-status` | wieder `🔒 <Name Slot 5>` |

- [ ] **Schritt 15: Fortschritt eintragen, committen**

---

## Aufgabe 6: ProtonVPN-GUI und alle Proton-Reste entfernen

**Dateien:** (Zeilen gemessen 2026-09-13 vor Aufgabe 2 — beim Bearbeiten an den Ankertexten orientieren)
- Ändern: `flake.nix:79-113` (Overlay-Block), `flake.nix:121` (Overlay-Liste)
- Löschen: `modules/protonvpn.nix`; Ändern: `configuration.nix:11`
- Ändern: `modules/network.nix:100-104`, `:122-140`, `:186-248`, `:278-280`
- Ändern: `modules/firewall.nix:15`, `:96-97`, `:121-125`, `:160-169`, `:226-231`, `:385-387`, `:398-556`
- Ändern: `home.nix:130`, `home.nix:1856-1902`
- Ändern: `modules/email-alerts.nix:262-295`
- Ändern: `modules/sops.nix:30-32`, `:55-56`, `:100-105`, `:117-118`
- Ändern: `modules/security.nix:831`, `modules/desktop.nix:155`, `modules/suricata.nix:36`

**Interfaces:**
- Konsumiert: funktionierende Tunnel aus Aufgaben 2–5 (Rückfall auf die GUI ist danach weg).
- Produziert: keine Proton-GUI-Artefakte; Output-Chain unverändert bis auf die Zeile 4b.
  Die Proton-Interfacenamen in der Output-Chain bleiben bis Aufgabe 7 stehen (harmlos, Aufgabe 7
  schreibt die Chain neu).

- [ ] **Schritt 1: Roter Test — Bestandsaufnahme**

```bash
rg -n -i 'proton|pvpn' --glob '*.nix' | rg -v '^home\.nix:(483|622):|apparmor-profiles\.nix:.*\.cache/Proton' | wc -l
```
Erwartet: deutlich > 0 (Ausgangswert notieren).

- [ ] **Schritt 2: `flake.nix`**

Den ganzen Block von `# ProtonVPN Kill Switch Fix (systemd-resolved 258 + IPv6 disabled)` bis
einschließlich der schließenden `};` von `protonvpnFixOverlay` löschen. Overlay-Liste:

```nix
          { nixpkgs.overlays = [ customOverlay ]; }
```

- [ ] **Schritt 3: `modules/protonvpn.nix` löschen, Import entfernen**

```bash
git rm modules/protonvpn.nix
```
In `configuration.nix` die Zeile `./modules/protonvpn.nix` löschen. Was davon noch gebraucht wird,
steht bereits in `modules/vpn.nix` (`wireguard`-Modul, `wireguard-tools`). Entfallen: `dummy`-Modul,
`/etc/wireguard`, `vpn-watchdog` (Dienst + abgeschalteter Timer).

- [ ] **Schritt 4: `modules/network.nix`**

(a) Kommentar über `unmanaged` — die fünf Zeilen ab `# ProtonVPN Kill-Switch-Interfaces` bis
`# → Kapert DNS BEVOR VPN steht …` löschen; die Zeile `# WWAN Modem ignorieren …` bleibt.

(b) In `dispatcherScripts` den zweiten Eintrag (`source = pkgs.writeText "fix-pvpn-killswitch-dns"` …
bis zu seinem `type = "basic"; }`) löschen; `no-hostname` bleibt.

(c) `cleanup-nm-connections`: Kommentarpunkte 1 und 3 und die Skriptteile
`# 1. ProtonVPN Kill Switch Connections entfernen` und `# 3. ProtonVPN GUI VPN-Verbindungen entfernen`
löschen. Der Kommentarkopf wird zu:

```nix
  # ==========================================
  # NM CONNECTION CLEANUP (vor jedem NM-Start)
  # ==========================================
  # Stale WiFi Profiles:
  #    Wenn WiFi-Einstellungen manuell geändert werden (GNOME Settings, nmcli),
  #    überschreibt NM die deklarative Konfiguration mit falschen Werten:
  #    - ipv4.method: manual statt auto (DHCP)
  #    - ipv6.method: auto statt disabled (IPv6-Leak!)
  #    - ignore-auto-dns: nein statt ja (Router-DNS statt Quad9)
  #    Durch Löschung vor NM-Start erstellt ensureProfiles ein frisches Profil.
  #    (Bis 2026-09-13 räumte der Dienst auch Profile der ProtonVPN-GUI weg.)
```
Das Skript behält nur die `Greenside4*`-Schleife (Kommentar `# 2.` → ohne Nummer).

(d) `networking.hosts`-Kommentar zu `rusty-vault.de`: Eintrag bleibt (Wirkung nicht Teil dieses
Umbaus), Kommentar ergänzen:

```nix
  # WORKAROUND: rusty-vault.de direkt zur Origin (umging 2026 den ProtonVPN-Resolver
  # 10.2.0.1, der DNSSEC nicht sauber unterstützte, solange die GUI proton0 mit
  # Domain=~. setzte). Seit der WireGuard-Umstellung (2026-09-13) ohne Anlass —
  # Entfernen erst nach Messung: resolvectl query rusty-vault.de mit Tunnel.
```

- [ ] **Schritt 5: `modules/firewall.nix`**

(a) Kopf, Zeile `# 5. ProtonVPN GUI (proton0) - verbindet nach Login` →
`# 5. vpn-boot.service (wg-1) - verbindet Slot 1 (modules/vpn.nix)`.

(b) Boot-Reihenfolge-Kommentar, die Zeilen `# 5. wg-quick-proton-cli.service …` und
`# 6. ProtonVPN GUI …` ersetzen durch `# 5. vpn-boot.service (Slot 1, modules/vpn.nix)`.

(c) Set löschen:
```nft
        # ProtonVPN API server IPs - populated by proton-api-update.service
        set proton_api {
          type ipv4_addr
          flags timeout
        }
```

(d) Input-Chain Regel 7: die vier Zeilen mit `iifname "proton-cli"` / `iifname "proton0"` löschen,
Kommentar `# 7. Syncthing - Over VPN interfaces (HYBRID MODE: CLI + GUI)` → `# 7. Syncthing - über VPN-Interfaces`.

(e) Output-Chain: Block `# 4b. ProtonVPN API-Zugriff auf physischen Interfaces` samt Regel
`… ip daddr @proton_api tcp dport … accept` (5 Kommentarzeilen + 1 Regel) löschen.

(f) rp-filter-Skript:
```nix
      # Setze loose rp_filter (2) für VPN-Interfaces (falls vorhanden)
      # Note: grep exits with 1 if no matches, so use || true to prevent script failure at boot
      VPN_IFACES=$(${pkgs.iproute2}/bin/ip -o link show | \
        ${pkgs.gnugrep}/bin/grep -E "^[0-9]+: (tun|wg)" | \
```

(g) Den ganzen Abschnitt von `# PROTON API IP UPDATE SERVICE` bis vor `# TAILSCALE API IP UPDATE SERVICE`
löschen — **außer** diesem Block, der Tailscale und die Boot-Reihenfolge betrifft und bleibt:

```nix
  # nftables NACH network-online starten (siehe Kommentar oben zur Service-Reihenfolge).
  systemd.services.nftables = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = lib.mkForce [ ];
  };
```
Gelöscht werden also `proton-api-seed`, `proton-api-update`, `systemd.timers.proton-api-update`
und ihre Kommentare.

- [ ] **Schritt 6: `home.nix`**

Zeile `proton-vpn # GUI zusätzlich zur CLI (umbenannt von protonvpn-gui)` löschen. Den Abschnitt
von `# PROTONVPN GUI - NUR auf manuellen Start (kein Autostart mehr)` (inkl. der `# ====`-Zeile
davor) bis einschließlich der schließenden `};` von `systemd.user.services.protonvpn-gui` löschen.
Die Keyring-Kommentare bei `home.nix:483` und `:622` bleiben (sie erklären das Backup-Format).

- [ ] **Schritt 7: `modules/email-alerts.nix`**

`# VPN Failure: Email wenn VPN dauerhaft down`, `systemd.services.vpn-failure-alert` und
`systemd.timers.vpn-failure-alert` mit ihrem Kommentar löschen. Eine Mail „VPN down“ ersetzt der
Kill-Switch plus die Leistenanzeige; ein neuer Alarm ist nicht Teil dieses Umbaus.

- [ ] **Schritt 8: `modules/sops.nix`**

Löschen: die drei Kommentarzeilen ab `# WireGuard Private Key für ProtonVPN`, die zwei ab
`# ProtonVPN WireGuard Secrets entfernt`, den auskommentierten Block ab `# ProtonVPN IP-Ranges`
(6 Zeilen), die zwei ab `# WireGuard CLI-Template entfernt`. An erster Stelle ergänzen:

```nix
    # WireGuard-Schlüssel der neun VPN-Slots (wireguard/slot1…9) werden in
    # modules/vpn.nix deklariert — dort, wo auch das NM-Template entsteht.
```

- [ ] **Schritt 9: Kommentare**

- `modules/security.nix:831`: `(jetzt 3 Interfaces:` + `proton0, wlp0s20f3, enp0s31f6)` →
  `(2 Interfaces: wlp0s20f3, enp0s31f6)`.
- `modules/desktop.nix:155`: `# Tray-Icon Support (wichtig für ProtonVPN)` → `# Tray-Icon Support`.
- `modules/suricata.nix:36`: `# Falls ProtonVPN wieder dauerhaft läuft: Block hier reaktivieren.` →
  `# Die WireGuard-Slots (wg-1…wg-9, seit 2026-09-13) wechseln das Interface — deshalb bewusst kein af-packet-Eintrag dafür.`

- [ ] **Schritt 10: Grüner Test — Bestandsaufnahme und Bau**

```bash
rg -n -i 'proton|pvpn' --glob '*.nix'
nix eval --json .#nixosConfigurations.nixos.config.nixpkgs.overlays --apply builtins.length
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
```
Erwartet: Treffer nur noch `home.nix:483`/`:622` (Keyring-Kommentare), `apparmor-profiles.nix`
(`deny @{HOME}/.cache/Proton/**` — harmlos), `network.nix` Hosts-Kommentar, `suricata.nix`
Historie-Kommentar (`proton0 ENTFERNT (2026-08-06)`), `modules/firewall.nix` Output-Chain
(`proton-cli`/`proton0`, bis Aufgabe 7). Overlays: `1`. Bau ohne Fehler.

- [ ] **Schritt 11: Commit**

```bash
git add -A flake.nix configuration.nix modules/network.nix modules/firewall.nix home.nix modules/email-alerts.nix modules/sops.nix modules/security.nix modules/desktop.nix modules/suricata.nix
git commit -m "ProtonVPN-GUI entfernt: Overlay, Watchdog, DNS-Dispatcher, API-Set, Alarm, Paket"
```

- [ ] **Schritt 12: [Nutzer] Aktivieren und Altlast-Datei entfernen**

```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
sudo rm -f /var/lib/proton-api-seed
```

- [ ] **Schritt 13: Messen, dass nichts mehr da ist und die Tunnel weiter tragen**

```bash
command -v protonvpn-app || echo "protonvpn-app: weg"
systemctl list-unit-files | rg -i 'proton|vpn-watchdog|vpn-failure' || echo "System-Units: weg"
systemctl --user list-unit-files | rg -i proton || echo "User-Units: weg"
nmcli -t -f NAME connection show | rg -i 'pvpn|proton' || echo "NM-Profile: weg"
ip -br link | rg -i 'pvpn|proton' || echo "Interfaces: weg"
lsmod | rg '^dummy ' || echo "dummy: nicht geladen (nach Neustart aussagekräftig)"
vpn 3 && jq -c '{slot, handshake_alter}' /run/vpn/status.json
```
Erwartet: alle „weg“-Zeilen, `vpn 3` erfolgreich mit Slot 3.

- [ ] **Schritt 14: Laufzeitreste der GUI im Home — Nutzer vorher fragen, dann löschen**

Nur ansehen:
```bash
du -sh ~/.config/Proton ~/.cache/Proton ~/.local/share/Proton 2>&1
```
Nach Zustimmung: `rm -rf ~/.config/Proton ~/.cache/Proton ~/.local/share/Proton`.
Keyring-Einträge der GUI löscht der Nutzer selbst in „Passwörter und Schlüssel“ (Seahorse),
Einträge mit „Proton“ im Namen — erst **nach** einem erfolgreichen Lauf von
`gnome-keyring-backup`, damit das Golden Backup nicht einen halben Stand sichert.

- [ ] **Schritt 15: Fortschritt eintragen, committen**

---

## Aufgabe 7: Kill-Switch (Stufe 2)

**Dateien:**
- Ändern: `modules/firewall.nix` — Modulkopf (Argument `vpnServer`), `let`-Block, Output-Chain komplett

**Interfaces:**
- Konsumiert: `vpnServer` (Endpunkte), Chain `direkt` + `vpn-direkt.service` (Aufgabe 3),
  `vpn` (Aufgabe 4), Statusfeld `killswitch` (Aufgabe 3).
- Produziert: Output-Chain `policy drop`; Log-Präfix `vpn-sperre: `.

- [ ] **Schritt 0: Voraussetzung prüfen**

In `docs/superpowers/plans/2026-09-12-nitrokey-fido2.md`, Abschnitt „Fortschritt“: Stehen die
Neustart-Tests von 7b noch aus → **Stopp**, Nutzer fragen. Zwei offene Baustellen mit Neustarts
gleichzeitig machen jeden Fehler doppeldeutig.

- [ ] **Schritt 1: Roter Test — der Kill-Switch fehlt**

```bash
jq .killswitch /run/vpn/status.json
vpn aus >/dev/null 2>&1; curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://example.com; echo "curl exit=$?"
vpn 1 >/dev/null 2>&1
```
Erwartet: `false`; ohne Tunnel `200` und `curl exit=0` — Verkehr fließt ungeschützt.

- [ ] **Schritt 2: `modules/firewall.nix` — Kopf und `let`**

Argumente: `{ config, lib, pkgs, id, vpnServer, ... }:`

Im `let`-Block `vpnRoutingTable = 51820;` (unbenutzt) löschen und `vpnPorts` ersetzen durch:

```nix
  # WireGuard-Endpunkte der neun Slots als nft-Konkatenation "ip . port, …".
  # Nur dorthin darf ohne Tunnel UDP raus (Handshake). Bis 2026-09-13 stand hier
  # "UDP 443/51820/88/1224/500/4500 zu JEDEM Ziel" — UDP 443 ist QUIC, Browser
  # wären damit am Kill-Switch vorbeigekommen.
  vpnEndpunkte = lib.concatMapStringsSep ", " (s: "${s.endpoint} . ${toString s.port}") vpnServer;
```

- [ ] **Schritt 3: Output-Chain ersetzen**

Alles von `# OUTPUT CHAIN` bis zur schließenden `}` der Output-Chain (vor `# FORWARD CHAIN`)
ersetzen durch:

```nft
        # OUTPUT CHAIN — KILL-SWITCH (seit 2026-09-13)
        # Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md
        # Ohne Tunnel geht nur raus, was ihn aufbaut (Handshake zu den neun Endpunkten,
        # DHCP), das lokale Netz und Tailscale. Ungeschützter Verkehr nur im Zustand
        # "Direkt": vpn-direkt.service füllt die Chain `direkt` (Befehl: vpn direkt).
        # Notfall ohne funktionierendes `vpn`: policy drop -> accept, nixos-rebuild.
        chain output {
          type filter hook output priority filter; policy drop;

          # 1. Loopback — auch DNS an den resolved-Stub 127.0.0.53
          oif lo accept

          # 2. Syncthing-Ratenlimit über den Tunnel (Anti-Exfiltration).
          #    Muss VOR "established" stehen, sonst trifft es nur das erste Paket.
          #    Bis 2026-09-13 stand es hinter "oifname proton0 accept" und griff nie.
          oifname "wg*" tcp dport ${toString syncthingPorts.tcp} limit rate over 10 mbytes/second drop
          oifname "wg*" udp dport ${toString syncthingPorts.quic} limit rate over 10 mbytes/second drop

          # 3. Bestehende Verbindungen — nur über Tunnel/Tailscale oder ins lokale Netz.
          #    Eine im Zustand "Direkt" geöffnete Verbindung soll nach dem Umschalten
          #    nicht am Tunnel vorbei weiterlaufen.
          ct state established,related oifname "wg*" accept
          ct state established,related oifname "tailscale0" accept
          ct state established,related ip daddr { ${localNetwork.subnet}, ${secondLocalNetwork.subnet}, ${remarkableNetwork.subnet} } accept

          # 4. Tunnel und Tailscale
          oifname "wg*" accept
          oifname "tailscale0" accept

          # 5. Tailscales eigene Pakete: tailscaled markiert seine Sockets mit 0x80000
          #    und routet sie über die Main-Tabelle am Tunnel vorbei (ip rule 5210).
          meta mark and 0xff0000 == 0x80000 accept

          # 5b. Bisherige Tailscale-Freigaben ohne Markierung. Die Zähler zeigen, ob sie
          #     neben 5 noch gebraucht werden (Messung Schritt 14). UDP 3478 zu jedem Ziel
          #     erlaubt auch Browsern STUN außen herum — WebRTC-Leck-Kandidat.
          udp dport 41641 counter accept
          ip daddr @tailscale_api tcp dport 443 counter accept
          udp dport 3478 counter accept

          # 6. Härtung — gilt auch im Zustand "Direkt"
          udp dport 5355 drop comment "Block LLMNR (credential theft risk)"
          udp dport 5353 drop comment "Block mDNS (information leakage)"
          meta nfproto ipv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept
          meta nfproto ipv6 ip6 daddr != fe80::/10 drop

          # 7. WireGuard-Handshake — nur zu den neun Endpunkten der Serverliste
          ip daddr . udp dport { ${vpnEndpunkte} } accept

          # 8. DHCP (client:68 -> server:67)
          udp sport 68 udp dport 67 accept

          # 9. Lokales Netz (unverändert aus der Chain vor 2026-09-13)
          ip daddr ${localNetwork.gateway} tcp dport { 80, 443 } accept
          ip daddr ${localNetwork.printerIP} tcp dport 631 accept
          ip daddr ${localNetwork.printerIP} tcp dport 9100 accept
          ip daddr 192.168.178.100 tcp dport { 22, 8006 } accept
          ip daddr 192.168.178.49 tcp dport { 22, 8096, 8920 } accept
          ip daddr ${localNetwork.subnet} icmp type echo-request accept
          ip daddr 192.168.178.51 tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip daddr 192.168.178.51 udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept
          ip daddr 192.168.178.51 icmp type echo-request accept
          ip daddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept
          ip daddr 255.255.255.255 udp dport ${toString syncthingPorts.discovery} accept
          ip daddr 192.168.178.255 udp dport ${toString syncthingPorts.discovery} accept
          ip daddr ${secondLocalNetwork.subnet} tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip daddr ${secondLocalNetwork.subnet} udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept
          ip daddr ${remarkableNetwork.subnet} tcp dport { 22, 80 } accept

          # 10. Zustand "Direkt" — leer, außer vpn-direkt.service ist aktiv
          jump direkt

          # 11. Sichtbar machen, was gesperrt wird (danach greift policy drop)
          limit rate 10/minute log prefix "vpn-sperre: "
        }
```

Entfallen gegenüber vorher (bewusst): DNS-Stub-Regeln (laufen über `lo`), DoT-Bootstrap zu
9.9.9.9 und DoT zu Mullvad über Proton-Interfaces (über den Tunnel greift Regel 4, außen herum nur
„Direkt“), `tcp/udp dport 853 drop` (fremdes DoT fällt ohne Tunnel unter `policy drop`, im Zustand
„Direkt“ filtert die Chain `direkt`), die breite UDP-Portfreigabe 4a.

- [ ] **Schritt 4: Auswertung und Bau (nft-Syntaxprüfung läuft mit)**

```bash
nix eval --raw .#nixosConfigurations.nixos.config.networking.nftables.ruleset | rg -c 'ip daddr \. udp dport \{ ([0-9.]+ \. [0-9]+, ){8}[0-9.]+ \. [0-9]+ \} accept'
nix eval --raw .#nixosConfigurations.nixos.config.networking.nftables.ruleset | rg -n 'policy drop|proton|dport \{ 443, 51820'
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
```
Erwartet: `1` (genau eine Regel mit neun Endpunkten — Werte nicht ausgeben); `policy drop` bei
input, forward und output, **kein** `proton`, keine alte Portliste; Bau ohne Fehler.

- [ ] **Schritt 5: Commit**

```bash
git add modules/firewall.nix
git commit -m "Kill-Switch: Output-Chain policy drop, Handshake nur zu den neun Endpunkten"
```

- [ ] **Schritt 6: [Nutzer] Aktivieren — nur `test`**

```nu
sudo nixos-rebuild test --flake /home/achim/nixos-config#nixos
```
`test` schreibt keinen Boot-Eintrag: Sperrt der Kill-Switch zu viel aus, holt ein Neustart den
alten Stand zurück.

- [ ] **Schritt 7: Gesperrt**

```bash
jq -c '{killswitch, slot}' /run/vpn/status.json
vpn aus
curl -s -m 5 -o /dev/null https://1.1.1.1; echo "Internet ohne Tunnel exit=$?"
curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://192.168.178.1; echo "Fritz!Box exit=$?"
tailscale status | head -3
journalctl -k --since -2min -g 'vpn-sperre' -o cat | tail -3
```
Erwartet: `killswitch` true; Internet `exit` ≠ 0 (28 oder 7); Fritz!Box `200`/`30x`, `exit=0`;
Tailscale zeigt Peers online; mindestens eine `vpn-sperre:`-Zeile (sonst `journalctl` **[Nutzer]**
mit sudo). Leiste: `⛔ gesperrt` grau. **[Nutzer]** zusätzlich: `tailscale ping -c 1 <homeserver>` → pong.

- [ ] **Schritt 8: Tunnel trägt, Umgehungsversuche scheitern**

```bash
vpn 3 && curl -s -m 10 https://am.i.mullvad.net/json | jq -r '.country'
curl -s -m 5 --interface wlp0s20f3 -o /dev/null https://1.1.1.1; echo "TCP außen herum exit=$?"
curl -s -m 5 --interface wlp0s20f3 -o /dev/null telnet://9.9.9.9:853; echo "DoT außen herum exit=$?"
nix shell --inputs-from . nixpkgs#dig -c dig @192.168.178.1 +time=3 +tries=1 example.com | rg 'status:|timed out|no servers'
nix shell --inputs-from . nixpkgs#curlHTTP3 -c curl -s -m 5 --http3-only --interface wlp0s20f3 -o /dev/null https://cloudflare-quic.com; echo "QUIC außen herum exit=$?"
```
Erwartet: Land von Slot 3; alle drei `exit` ≠ 0; DNS an die Fritz!Box `timed out`/`no servers`.
Heißt das Paket `curlHTTP3` im gepinnten nixpkgs anders: `nix search --inputs-from . nixpkgs curl` und
das HTTP/3-Paket nehmen — nicht auslassen, QUIC war das konkrete Leck.

- [ ] **Schritt 9: [Nutzer] Leck-Mitschnitt beim Surfen**

Mit aktivem Tunnel 60 s im Browser surfen (Video, mehrere Seiten), parallel:
```nu
sudo timeout 60 tcpdump -ni wlp0s20f3 -c 200 'not udp port 51820 and not net 192.168.178.0/24 and not net 192.168.188.0/24'
```
Erwartet: nur Tailscale-Verkehr (UDP zu Peers/DERP, TCP 443 zu Tailscale-Servern) oder gar
nichts. Jedes andere Paket: **Stopp**, Befund. Außerdem in LibreWolf
`https://browserleaks.com/webrtc` öffnen → keine Heim-IP, nur die Proton-IP.

- [ ] **Schritt 10: [Nutzer] Tunnel bricht weg**

```nu
sudo nft insert rule inet filter output oifname "wlp0s20f3" udp dport 51820 drop
```
Im Tool-Bash:
```bash
curl -s -m 5 -o /dev/null https://1.1.1.1; echo "exit=$?"
sleep 200; jq -c '{slot, handshake_alter}' /run/vpn/status.json
```
Erwartet: `exit` ≠ 0 sofort; nach 200 s `handshake_alter` ≥ 180, Leiste `⚠ <Name>` orange.
Aufräumen **[Nutzer]**: `sudo systemctl reload nftables` (lädt das deklarierte Ruleset neu), dann
im Tool-Bash nach 30 s `handshake_alter` klein, Leiste grün.

- [ ] **Schritt 11: Direkt**

**[Nutzer]** Leiste → „⚠ Direkt …“ → Direkt verbinden. Im Tool-Bash:
```bash
sleep 3; jq -c '{slot, direkt}' /run/vpn/status.json
curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://example.com; echo "exit=$?"
curl -s -m 5 -o /dev/null telnet://1.1.1.1:853; echo "fremdes DoT exit=$?"
vpn 5; jq -c '{slot, direkt}' /run/vpn/status.json
```
Erwartet: `{"slot":null,"direkt":true}`; `200`, `exit=0`; fremdes DoT `exit` ≠ 0;
danach `{"slot":5,"direkt":false}`.

- [ ] **Schritt 12: [Nutzer] Übernehmen**

Erst wenn 7–11 bestanden sind:
```nu
sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos
```

- [ ] **Schritt 13: [Nutzer] Neustart, Suspend, WLAN**

| Handlung | Messung | Erwartung |
|---|---|---|
| Neustart, **vor** dem Login per SSH von .51 oder Tailscale: `ssh root@<laptop> 'jq -c . /run/vpn/status.json'` | Status | `slot` 1, frischer Handshake, `killswitch` true, `direkt` false |
| Anmelden | Leiste, `jq .slot /run/vpn/status.json` | gemerkter Slot |
| `vpn direkt`, dann Neustart, anmelden | Leiste | nicht `DIREKT`, sondern Slot |
| Deckel 2 min zu, auf | nach ≤ 30 s | Handshake frisch, Leiste grün |
| anderes WLAN (Handy-Hotspot) | `vpn status`, Exit-Land | Tunnel trägt weiter |

(Ist SSH vor dem Login nicht möglich: Zeile 1 nach dem Login mit `journalctl -b -u vpn-boot` belegen.)

- [ ] **Schritt 14: Messung Tailscale-Altregeln (nach ≥ 30 min Betrieb mit Tailscale)**

**[Nutzer]**:
```nu
sudo nft list chain inet filter output | lines | where $it =~ 'counter'
```
Erwartet und Entscheidung: Stehen alle drei Zähler auf `packets 0`, obwohl Tailscale in der
Zeit Peers erreicht hat → Regel 5 reicht; die drei Regeln 5b werden entfernt (eigener Commit
„Kill-Switch: Tailscale nur noch über Socket-Markierung“, erneut Schritt 7 + WebRTC-Test aus 9).
Zählt eine davon: Befund an den Nutzer, Regeln bleiben.

- [ ] **Schritt 15: Fortschritt eintragen, committen**

---

## Aufgabe 8: Dokumentation nachziehen

**Dateien:**
- Ändern: `README.md:28`, `:50`, `:126`, `:259-275`
- Ändern: `docs/SECURITY-HARDENING.md:158`, `docs/SECRET-ROTATION-POLICY.md:31`, `:37`,
  `docs/SECRET-ROTATION-LOG.md:19`, `docs/SECURITY-PROCEDURES.md:189`
- Löschen: `docs/TODO-SOPS-PROTONVPN.md`
- Ändern: Spec-Status, Fortschrittstabelle dieses Plans
- Unverändert (Historie): `docs/DNS-BOOT-FIX-2026-02-05.md`, `docs/MIGRATION-IPTABLES-TO-NFTABLES.md`

**Interfaces:** keine.

- [ ] **Schritt 1: Roter Test**

```bash
rg -n -i 'proton' README.md docs/SECURITY-HARDENING.md docs/SECRET-ROTATION-POLICY.md docs/SECRET-ROTATION-LOG.md docs/SECURITY-PROCEDURES.md; ls docs/TODO-SOPS-PROTONVPN.md
```
Erwartet: Treffer in allen fünf Dateien, TODO-Datei vorhanden.

- [ ] **Schritt 2: `README.md`**

Zeile 28: `| **VPN** | ProtonVPN GUI (WireGuard, Auto-Connect, Kill-Switch) |` →
`| **VPN** | Neun WireGuard-Slots (Proton), Umschalten per Super+Alt+0…9 und Leiste, Kill-Switch |`

Zeile 50: `├── protonvpn.nix     # WireGuard Auto-Connect` →
`├── vpn.nix           # WireGuard-Slots, vpn-Befehl, Status, Direkt`

Zeile 126: `… + VPN (proton0)` → `(die WireGuard-Slots wechseln das Interface und werden nicht mitgeschnitten)`

Abschnitte `### firewall.nix` und `### protonvpn.nix` ersetzen durch:

```markdown
### firewall.nix

Kill-Switch mit nftables:
- Output-Policy DROP; ohne Tunnel nur WireGuard-Handshake zu den neun Endpunkten, DHCP,
  lokales Netz und Tailscale
- Zustand „Direkt“ (bewusst ungeschützt, z. B. Captive Portal) über die Chain `direkt`
- Verworfene Pakete im Kernel-Log mit Präfix `vpn-sperre:`
- Port-Scan Detection, mDNS/LLMNR-Sperre, IPv6-Leak-Sperre
- Syncthing im lokalen Netz und über den Tunnel (Ratenlimit über den Tunnel)

### vpn.nix

Neun Proton-WireGuard-Server als NetworkManager-Profile `wg-1`…`wg-9`:
- Serverliste aus dem privaten Flake-Input `identity`, Schlüssel aus SOPS
- `vpn 1…9 | aus | direkt | login | status` — prüft jede Umschaltung an der Exit-IP
- `vpn-status` misst Handshake und Kill-Switch nach `/run/vpn/status.json`
- Leiste: Erweiterung `vpn-indikator@local` (`modules/home/vpn.nix`), Kürzel Super+Alt+0…9
- Beim Boot Slot 1, nach dem Login der zuletzt benutzte Slot
```

- [ ] **Schritt 3: Sicherheitsdokumente**

- `docs/SECURITY-HARDENING.md:158`: `- ✅ VPN Kill-Switch (ProtonVPN WireGuard)` →
  `- ✅ VPN Kill-Switch (nftables, WireGuard-Slots, seit 2026-09-13 wieder aktiv)`
- `docs/SECRET-ROTATION-POLICY.md:31`: → `- WireGuard-Schlüssel der VPN-Slots (\`wireguard/slot1…9\`)`
- `docs/SECRET-ROTATION-POLICY.md:37`: → `2. VPN: im Proton-Konto neue WireGuard-Konfigurationen erzeugen, alte widerrufen; Serverliste (homeserver-secrets/vpn/laptop.nix) und SOPS-Schlüssel ersetzen (Aufgabe 1 des Plans 2026-09-13-wireguard-statt-proton-gui)`
- `docs/SECRET-ROTATION-LOG.md:19`: → `| WireGuard-Schlüssel VPN-Slots 1–9 | - | 2026-09-13 | ✅ neu erzeugt | - | Proton-Downloads 2026-09-13 |`
- `docs/SECURITY-PROCEDURES.md:189`: → `- ⚠️ WireGuard-Schlüssel der VPN-Slots (bei Verdacht auf Kompromittierung: im Proton-Konto widerrufen)`

- [ ] **Schritt 4: TODO-Datei löschen, Spec-Status setzen**

```bash
git rm docs/TODO-SOPS-PROTONVPN.md
```
In der Spec `**Status:** Entwurf, wartet auf Freigabe` → `**Status:** umgesetzt (Plan docs/superpowers/plans/2026-09-13-wireguard-statt-proton-gui.md)`.

- [ ] **Schritt 5: Grüner Test**

```bash
rg -n -i 'proton' README.md docs/SECURITY-HARDENING.md docs/SECRET-ROTATION-POLICY.md docs/SECRET-ROTATION-LOG.md docs/SECURITY-PROCEDURES.md
```
Erwartet: nur Treffer, die Proton als Anbieter der Konfigurationen nennen (README Zeile 28,
Rotation-Policy/-Procedures „Proton-Konto“), keine GUI, kein `proton0`, kein `protonvpn.nix`.

- [ ] **Schritt 6: Commit**

```bash
git add -A README.md docs/
git commit -m "Doku: WireGuard-Slots und Kill-Switch statt ProtonVPN-GUI"
```

- [ ] **Schritt 7: Auto-Memory aktualisieren** (außerhalb des Repos)

`/home/achim/.claude/projects/-home-achim-nixos-config/memory/`: neue Datei zur WireGuard-Umstellung
(Befehl `vpn`, Wahrheit Chain `direkt`, Statusdatei, Stufen); in `MEMORY.md` die Einträge
„ProtonVPN GUI Kill-Switch DNS-Hijack“ und „ProtonVPN-GUI startet nicht“ als historisch markieren
und auf die neue Datei verweisen; `protonvpn-gui-start-minimized-hides-window.md` und
`firewall-details.md` prüfen und anpassen.

---

## Was dieser Plan nicht tut

- rp_filter-Härtung der physischen Interfaces (Nebenbefund der Spec: `wlp0s20f3` steht auf 2)
- `tailscale_api` entfernen (nur die Messung in Aufgabe 7 Schritt 14 entscheidet über 5b)
- DNS auf Protons Resolver umstellen (Messung in Aufgabe 2 Schritt 11, Entscheidung beim Nutzer)
- Port-Forwarding, gleichzeitig aktive Tunnel, Split-Routing
- `/etc/hosts`-Workarounds (`youtube.com`, `rusty-vault.de`) entfernen
- einen Mail-Alarm bei dauerhaft fehlendem Tunnel (Kill-Switch + Leiste ersetzen ihn)
