# WireGuard-Profile mit Kill-Switch und Leistenanzeige statt ProtonVPN-GUI

**Datum:** 2026-09-13
**Status:** freigegeben 2026-09-13

> **Beim Planen verfeinert** (Begründungen im Plan
> `docs/superpowers/plans/2026-09-13-wireguard-statt-proton-gui.md`, Abschnitt „Verfeinerungen“):
> kein NM-Autoconnect, stattdessen `vpn-boot.service`; „Direkt“ wird an der Chain gemessen, nicht
> am Unit-Zustand, `PartOf` entfällt; Statusdatei `/run/vpn/status.json` mit zusätzlichem Feld
> `killswitch` und Zustand „offen“; Syncthing-Ratenlimit vor `established`. Wo diese Spec davon
> abweicht, gilt der Plan.

## Ziel

Die ProtonVPN-GUI fliegt komplett raus. An ihre Stelle treten:

1. **Neun feste WireGuard-Profile** (Proton-Konfigurationen), per Tastenkürzel umschaltbar:
   `Super+Shift+1…9` wählt Server 1–9, `Super+Shift+0` trennt.
2. **Eine Anzeige oben in der GNOME-Leiste**, die den aktiven Server zeigt und per Klick ein Menü
   mit allen Servern, „Aus“, „Direkt“ und dem gemessenen Zustand (Handshake-Alter, Exit-IP,
   rx/tx) öffnet.
3. **Ein Kill-Switch**, der ohne Tunnel alles sperrt außer dem, was den Tunnel aufbaut, dem LAN
   und Tailscale. Ungeschützter Zugang nur über den bewusst gewählten Zustand „Direkt“.

## Ist-Zustand (gemessen)

| Sache | Befund | Wie gemessen |
|---|---|---|
| GNOME Shell | 50.4 | `gnome-shell --version` |
| NetworkManager | 1.58.0 | `NetworkManager --version` |
| ProtonVPN-GUI | installiert, User-Unit `protonvpn-gui` **linked**, läuft nicht | `systemctl --user is-enabled`, `pgrep` |
| Proton-Interfaces | keine (`proton0`, `pvpnksintrf0` fehlen) | `ip -br link` |
| Kill-Switch | **aus** seit `fd81be4` (2026-06-24), Output-Chain `policy accept` | `modules/firewall.nix:203` |
| Tailscale | `tailscaled` aktiv, `ip rule` 5210–5270 (fwmark `0x80000`, Tabelle 52) | `systemctl is-active`, `ip rule` |
| rp_filter | `all=2`, `default=2`, `wlp0s20f3=2` | `sysctl` |
| `src_valid_mark` | 0 | `sysctl` |
| Repo | **öffentlich** | `gh repo view --json visibility` |

### Mängel im Altbestand, die ohne `policy accept` zu Lecks würden

- **Regel 4a** (`firewall.nix:224`) erlaubt auf physischen Interfaces UDP 443/51820/88/1224/500/4500
  **zu jedem Ziel**. UDP 443 ist QUIC — Browser gingen per HTTP/3 am Tunnel vorbei.
- **Regel 7** erlaubt DoT zu 9.9.9.9 über jedes Interface.
- **`ct state established,related accept`** gilt für alle Interfaces. Eine im ungeschützten
  Zustand geöffnete Verbindung liefe nach dem Umschalten weiter.
- **Regel 14** (Syncthing-Ratenlimit, `firewall.nix:295`) steht hinter
  `oifname "proton0" accept` und wird deshalb **nie erreicht**.

### Nebenbefund, nicht Teil dieses Umbaus

Das rp_filter-Skript (`firewall.nix:357 ff.`) soll physische Interfaces auf *strict* (1) setzen.
Gemessen steht `wlp0s20f3` auf 2, und wegen `all.rp_filter = 2` wäre der effektive Wert ohnehin
`max(all, iface) = 2`. Die Härtung ist nur behauptet. Für die neuen `wg-*`-Interfaces ist das
günstig (`default=2` → loose, nichts zu tun); für die physischen gehört es in einen eigenen Schritt.

## Entscheidungen

| Frage | Entscheidung | Begründung |
|---|---|---|
| Anzahl Server | **9** | Ziffern 1–9, 0 = Aus |
| Was zeigt/kann die Leiste | Anzeige, Klick-Menü zum Umschalten, gemessener Zustand | Ein WireGuard-Profil gilt in NM auch ohne je erfolgten Handshake als „aktiv“; nur ein Name würde Schutz vortäuschen |
| DNS bei aktivem Tunnel | **globales DoT (Quad9/Mullvad) behalten**, `DNS =` aus der Proton-Konfiguration ignorieren | Strenge DNSSEC bleibt; 10.2.0.1 validiert nicht sauber |
| Start und Tunnelausfall | **Autoconnect + Kill-Switch** | – |
| Bedeutung von „Aus“ | **trennt und sperrt**; ungeschützt nur über „Direkt“ | Ein versehentliches „Aus“ darf nicht ungeschützt sein |
| „Direkt“ | eigener Zustand, nur per Menü mit Bestätigung, **überlebt weder Reboot noch nftables-Neustart** | Captive Portals brauchen ihn; vergessen darf man ihn nicht |
| Tastenkürzel | fest pro Slot, `Super+Shift+1…9`, `Super+Shift+0` = Aus, kein Kürzel für Direkt | `Super+1…9` ist in GNOME belegt; Durchschalten baut bei jedem Schritt einen Tunnel auf; Super+Alt scheidet aus, weil das Layout us-umlaut die linke Alt zur Umlaut-Ebene macht und das de-Layout keine Alt-Taste hat (gemessen 2026-09-16) |
| Anzeige-Technik | **eigene GNOME-Shell-Erweiterung im Repo** | Ereignisgesteuert über `NM.Client`, farbige Beschriftung; Aufwand bei GNOME-Upgrades vertretbar, weil eigener kleiner Code |
| Ort der Serverdaten | **privates Repo** `homeserver-secrets`, über den Flake-Input `identity` | Das öffentliche Repo soll nicht zeigen, welche Server/Länder genutzt werden; die Endpunkte werden zur Bauzeit gebraucht, SOPS scheidet dafür aus |
| Private Schlüssel | SOPS, `secrets/secrets.yaml` → `wireguard/slot1…9` | – |
| IPv6 aus den Proton-Konfigurationen | **nicht übernehmen** | IPv6 ist im Kernel aus und wird in der Firewall verworfen |
| Proton-Kontingent | unkritisch | Proton: Anzahl Konfigurationen unbegrenzt; es zählen nur gleichzeitig aktive Verbindungen, vom Laptop immer höchstens eine |

## Bausteine

| # | Baustein | Ort | Aufgabe |
|---|---|---|---|
| 1 | Serverliste | `homeserver-secrets/vpn/laptop.nix` | 9 Einträge `{ slot, name, endpoint, port, serverPublicKey, address }` |
| 2 | Private Schlüssel | `secrets/secrets.yaml` | `wireguard/slot1…9`; ein SOPS-Template erzeugt eine Env-Datei `WG1_KEY=…` bis `WG9_KEY=…` |
| 3 | Tunnel-Profile | `modules/vpn.nix` (ersetzt `modules/protonvpn.nix`) | `networking.networkmanager.ensureProfiles`, `environmentFiles` = Template aus 2 |
| 4 | Kill-Switch | `modules/firewall.nix` | Output-Chain `policy drop`, Regeln siehe unten, leere Chain `direkt` |
| 5 | `vpn-direkt.service` | `modules/vpn.nix` | oneshot, `RemainAfterExit`; Start: `nft add rule … direkt accept`, Stopp: `nft flush chain … direkt`; `PartOf=nftables.service`, kein `wantedBy`; polkit-Regel erlaubt dem Nutzer nur Start/Stopp genau dieser Unit |
| 6 | `vpn-status.service` | `modules/vpn.nix` | root, Schleife alle 5 s, schreibt atomar (tmp + `mv`) `/run/vpn-status.json`, Rechte 0644 |
| 7 | `vpn`-Befehl | `modules/vpn.nix`, `writeShellApplication` | `vpn 1…9`, `vpn aus`, `vpn direkt`, `vpn status`; einziger Umschaltpfad für Menü, Kürzel und Terminal |
| 8 | Login-Autoconnect | `home.nix`, User-Unit `vpn-login` | wechselt auf den zuletzt benutzten Slot, falls ≠ 1 |
| 9 | Leisten-Erweiterung | `home/vpn-indikator/` (`vpn-indikator@local`) | liest nur Statusdateien, ruft nur `vpn` auf |
| 10 | Tastenkürzel | `home.nix`, `dconf.settings` custom-keybindings | `Super+Shift+1…9` → `vpn n`, `Super+Shift+0` → `vpn aus` |

### Serverliste (Form, Beispielwerte)

```nix
# homeserver-secrets/vpn/laptop.nix
[
  { slot = 1; name = "CH-1"; endpoint = "203.0.113.10"; port = 51820;
    serverPublicKey = "…="; address = "10.2.0.2/32"; }
  # … bis slot = 9
]
```

### NetworkManager-Profil pro Slot

- `connection.id = wg-<n>`, `connection.interface-name = wg-<n>`, `type = wireguard`
- `connection.autoconnect = true` **nur** für Slot 1, sonst `false`
- `wireguard.private-key = $WG<n>_KEY`
- `wireguard-peer.<serverPublicKey>`: `endpoint = <endpoint>:<port>`, `allowed-ips = 0.0.0.0/0`,
  `persistent-keepalive = 25`
- `ipv4.method = manual`, `ipv4.address1 = <address>`, **kein** `ipv4.dns`
- `ipv6.method = disabled`

`persistent-keepalive` ist Pflicht: Ohne Verkehr handshaket WireGuard nicht, ein ruhender Tunnel
sähe nach 180 s aus wie ein hängender.

### Statusdateien

`/run/vpn-status.json` (root, von `vpn-status`):

```json
{ "zeit": 1789310270, "slot": 2, "name": "CH-2", "handshake_alter": 37,
  "rx": 123456, "tx": 65432, "direkt": false }
```

`slot` ist `null`, wenn kein `wg-*` existiert. `handshake_alter` ist `null`, wenn nie ein
Handshake stattfand.

`$XDG_RUNTIME_DIR/vpn/exit.json` (Nutzer, von `vpn`): `{ "slot": 2, "ip": "…", "zeit": … }`.
Gilt nur, solange `slot` mit dem aktiven übereinstimmt.

## Zustände

| Zustand | Bedingung | Leiste |
|---|---|---|
| verbunden | Profil aktiv, Handshake < 180 s | `🔒 CH-2` |
| hängt | Profil aktiv, kein Handshake oder ≥ 180 s | `⚠ CH-2` orange |
| gesperrt | kein Profil aktiv, `direkt` inaktiv | `⛔ gesperrt` grau |
| direkt | `vpn-direkt.service` aktiv | `⚠ DIREKT` rot |
| unbekannt | `/run/vpn-status.json` fehlt oder älter als 15 s | `? VPN` grau |

180 s, weil WireGuard bei Verkehr spätestens alle 120 s neu verhandelt.

## Abläufe

### `vpn <n>`

1. `flock -n` auf `$XDG_RUNTIME_DIR/vpn/lock`; belegt → Meldung „Umschaltung läuft“, Ende.
2. Alle aktiven `wg-*` außer `wg-<n>` trennen (Lücke ~1 s, der Kill-Switch sperrt währenddessen).
3. `nmcli con up wg-<n>`.
4. **Wirkung prüfen:** Exit-IP durch den Tunnel abfragen, bis 15 s. Nur eine Antwort belegt, dass
   der Tunnel trägt (`nmcli` meldet bei WireGuard Erfolg ohne Handshake). Den Endpunkt dafür
   im Plan an einem echten Tunnel festlegen.
5. Erfolg → `exit.json` schreiben, Slot nach `$XDG_STATE_HOME/vpn/letzter` merken, Meldung
   `🔒 CH-2 · Exit <ip>`.
6. Fehlschlag → Profil **bleibt aktiv** (WireGuard versucht weiter), kritische Meldung, die stehen
   bleibt.
7. War `vpn-direkt` aktiv: erst **nach** bestätigtem Tunnel stoppen. Scheitert der Tunnel, bleibt
   „Direkt“ sichtbar bestehen.

### `vpn aus`

Alle `wg-*` trennen, `vpn-direkt` stoppen → gesperrt.

### `vpn direkt`

Alle `wg-*` trennen (ein Tunnel würde das Captive Portal verdecken), `vpn-direkt` starten.
Die Bestätigung fragt die Erweiterung, nicht `vpn`.

### Boot und Login

- Beim Boot verbindet NM `wg-1` systemweit — sonst wären Mail-Alarme, CVE-Monitor und
  Suricata-Updates bis zum Login ausgesperrt.
- Beim Login wechselt `vpn-login` auf den gemerkten Slot, falls ≠ 1.
- **Zu prüfen:** dass NM `wg-1` nach `vpn aus` nicht von selbst wieder verbindet (nach
  Kenntnisstand blockiert manuelles Trennen das Autoconnect bis zum Neustart). Stimmt das nicht,
  bekommt `vpn aus` einen Gegenzug.

## Firewall

### Output-Chain, `policy drop`, in dieser Reihenfolge

1. `oif lo accept`
2. `ct state established,related` → accept **nur** bei `oifname { "wg*", "tailscale0" }` oder
   Ziel in LAN, Server-Netz oder reMarkable-Netz
3. Syncthing-Ratenlimit mit `oifname "wg*"` (vorher unerreichbar, siehe oben)
4. `oifname { "wg*", "tailscale0" } accept`
5. `meta mark & 0xff0000 == 0x80000 accept` — Tailscales eigene Pakete, die über die
   Main-Tabelle am Tunnel vorbei hinausgehen
6. LLMNR-/mDNS-Drops, IPv6-Leak-Drop (gelten auch in „Direkt“)
7. `ip daddr . udp dport { <9 Endpunkte> } accept` — ersetzt 4a, erzeugt aus der Serverliste
8. DHCP, ICMPv6-ND, LAN-Regeln (Fritz!Box, Drucker, Proxmox, Jellyfin, .51, Syncthing,
   Server-Netz, reMarkable) unverändert
9. `jump direkt`
10. `log prefix "vpn-sperre: " limit rate 10/minute`

**Chain `direkt`:** leer; bei aktivem Dienst
`tcp dport 853 ip daddr != { 9.9.9.9, 194.242.2.2 } drop` gefolgt von `accept`.

Die Regeln 7 (DoT Bootstrap) und 8 (DoT Mullvad via Proton-Interfaces) des Altbestands entfallen:
Über den Tunnel greift Regel 4, außen herum nur „Direkt“.

### Input-Chain

`proton0`/`proton-cli` in den Syncthing-Regeln durch `wg*` ersetzen (`wg*` ist dort bereits
vorhanden → Proton-Zeilen einfach streichen).

### Tailscale

Die Regeln `tailscale_api` und UDP 3478/41641 bleiben vorerst. Ob Regel 5 sie überflüssig macht,
wird gemessen, entfernt wird in diesem Umbau nichts davon.

## Was entfällt

- `protonvpnFixOverlay` in `flake.nix`
- `modules/protonvpn.nix` (Watchdog, `dummy`-Modul, `/etc/wireguard`) → ersetzt durch `modules/vpn.nix`
- in `modules/network.nix`: Dispatcher `fix-pvpn-killswitch-dns`, Aufräumen der `pvpn-*`-Profile,
  zugehörige Kommentare
- in `modules/firewall.nix`: Set `proton_api`, `proton-api-seed`, `proton-api-update` (+ Timer),
  `/var/lib/proton-api-seed`, Proton-Interfacenamen, veraltete Kommentare zur Boot-Reihenfolge
- in `home.nix`: Paket `proton-vpn`, User-Unit `protonvpn-gui`
- in `modules/email-alerts.nix`: `vpn-failure-alert` (seit `fd81be4` ohnehin aus)
- in `modules/sops.nix`: tote Proton-Kommentare und das TODO zu `protonvpn/ip-ranges`
- Kommentare in `desktop.nix` (appindicator „wichtig für ProtonVPN“ — Paket bleibt),
  `suricata.nix`, `apparmor-profiles.nix` (`~/.cache/Proton`-Deny bleibt harmlos, Kommentar anpassen)

Laufzeitreste außerhalb der Konfiguration (`~/.config/Proton`, `~/.cache/Proton`, Keyring-Einträge
der GUI) werden im Plan einmalig aufgeräumt, nachdem die neuen Tunnel belegt funktionieren.

## Fehlerquellen, die eine Anzeige vortäuschen könnten

| Quelle | Gegenmaßnahme |
|---|---|
| Profil aktiv, nie Handshake | Zustand „hängt“ aus `handshake_alter`, nicht aus NM |
| Ruhender Tunnel ohne Handshake | `persistent-keepalive = 25` |
| Status-Dienst tot | Datei älter als 15 s → „unbekannt“ |
| Erweiterung nach GNOME-Upgrade inaktiv | Anzeige fehlt sichtbar; Kill-Switch, Kürzel und `vpn` sind unabhängig |
| `nixos-rebuild` startet nftables neu | `PartOf` beendet „Direkt“ → gesperrt; Tunnel läuft weiter |
| Exit-IP veraltet nach Slotwechsel | `exit.json` trägt den Slot und gilt nur für ihn |

## Einführung

1. **Stufe 1:** Serverliste, Schlüssel, Profile, `vpn`, Status, Erweiterung, Kürzel; GUI raus.
   Output-Chain bleibt `policy accept`. Tunneltests laufen.
2. **Stufe 2:** Kill-Switch. Zuerst `nixos-rebuild test` (ein Neustart holt die vorige Generation
   zurück), `switch` erst nach bestandenen Sperrtests.

Die Neustart-Tests des Nitrokey-Umbaus (`docs/superpowers/plans/2026-09-12-nitrokey-fido2.md`)
sollten vor Stufe 2 abgeschlossen sein.

## Tests (Zustand messen, nicht Exit-Code)

| Test | Messung | Erwartung |
|---|---|---|
| Jeder der 9 Slots | `vpn n`, Exit-IP | Proton-IP im erwarteten Land, nicht die Heim-IP |
| Kein DNS am Tunnel | `resolvectl status wg-n` | kein DNS-Server |
| DNS-/QUIC-Leck | `tcpdump -i wlp0s20f3` beim Surfen und bei `curl --http3` | nur UDP zum Endpunkt und LAN |
| Gesperrt | `vpn aus`, `curl -m5 https://1.1.1.1` | schlägt fehl, `vpn-sperre:` im Journal |
| Gesperrt: LAN, Tailscale | Fritz!Box-Webinterface, `tailscale ping <homeserver>` | erreichbar |
| Tunnel bricht weg | Endpunkt per nft vorübergehend blocken | kein Verkehr auf `wlp0s20f3`, nach ≤ 180 s `⚠` |
| Autoconnect-Sperre | `vpn aus`, 60 s warten | `wg-1` bleibt getrennt |
| Direkt | Menü → Direkt → `curl` | geht, `⚠ DIREKT` |
| Direkt endet | `systemctl restart nftables` / Neustart | gesperrt / Slot 1 |
| Status-Dienst tot | `systemctl stop vpn-status` | nach ≤ 15 s `? VPN` |
| Suspend, WLAN-Wechsel | Deckel zu/auf, anderes WLAN | Handshake erneuert, Anzeige grün |
| GUI weg | `nmcli con`, `ip link`, `command -v protonvpn-app` | kein `pvpn*`, kein `proton0`, kein Programm |

## Nicht Teil dieses Umbaus

- rp_filter-Härtung der physischen Interfaces (Nebenbefund oben)
- Entfernen von `tailscale_api`
- Port-Forwarding (NAT-PMP)
- Mehrere gleichzeitig aktive Tunnel / Split-Routing
