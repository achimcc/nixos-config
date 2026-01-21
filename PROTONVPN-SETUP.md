# ProtonVPN Auto-Connect Setup

## Übersicht

ProtonVPN ist jetzt so konfiguriert, dass es **automatisch beim Boot** (vor dem Login) eine VPN-Verbindung aufbaut. Die Credentials werden sicher mit **sops** verschlüsselt gespeichert.

## Schritt-für-Schritt Anleitung

### 1. Host Age Key generieren (falls noch nicht geschehen)

Nach dem ersten Deployment wird ein Age Key automatisch generiert:

```bash
# Key aus SSH Host Key ableiten
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
```

Kopiere den Output (beginnt mit `age1...`) und füge ihn in `.sops.yaml` ein:

```yaml
keys:
  - &user_achim age1rr0acs6r4eyxv2tlhp8xrj6ktzflh97mqpxcu2uup276cgulavwqt0jv64
  - &host_achim-laptop age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # <-- Hier einfügen

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *user_achim
          - *host_achim-laptop  # <-- Aktivieren
```

### 2. Secrets-Datei erstellen

Erstelle die verschlüsselte Secrets-Datei:

```bash
cd /Users/achimschneider/achim/nix-os-config

# Secrets-Datei erstellen (falls noch nicht vorhanden)
sops secrets/secrets.yaml
```

Füge folgende Einträge hinzu:

```yaml
protonvpn-username: dein-proton-username
protonvpn-password: dein-proton-passwort
```

**Wichtig:** Verwende deine **ProtonVPN/OpenVPN Credentials**, nicht deine Account-Login-Daten!

Diese findest du auf der ProtonVPN-Website unter:
→ Account → OpenVPN/IKEv2 username and password

### 3. System neu builden

```bash
sudo nixos-rebuild switch --flake /Users/achimschneider/achim/nix-os-config#achim-laptop
```

### 4. Überprüfung

Nach dem Reboot sollte ProtonVPN automatisch verbunden sein:

```bash
# VPN Status prüfen
sudo protonvpn-cli status

# Systemd Service prüfen
sudo systemctl status protonvpn-autoconnect.service

# Logs anschauen
sudo journalctl -u protonvpn-autoconnect.service -f
```

## Wie es funktioniert

1. **Boot** → Netzwerk kommt online
2. **systemd-Service** `protonvpn-autoconnect.service` startet
3. Service liest verschlüsselte Credentials aus `/run/secrets/`
4. ProtonVPN CLI verbindet mit schnellstem deutschen Server (UDP)
5. **Display Manager** (Login-Screen) startet → Du bist bereits über VPN verbunden
6. **Reconnect-Service** überwacht die Verbindung und stellt sie bei Bedarf wieder her

## Konfiguration anpassen

### Anderes Land/Server wählen

Bearbeite `modules/protonvpn.nix`:

```nix
# Zeile 48: Ändere --cc DE zu einem anderen Land
${pkgs.protonvpn-cli}/bin/protonvpn-cli c --cc US -p UDP  # USA
${pkgs.protonvpn-cli}/bin/protonvpn-cli c --cc CH -p UDP  # Schweiz
```

### Spezifischen Server wählen

```nix
${pkgs.protonvpn-cli}/bin/protonvpn-cli c de-123 -p UDP  # Spezifischer Server
```

### TCP statt UDP verwenden

```nix
${pkgs.protonvpn-cli}/bin/protonvpn-cli c --cc DE -p TCP
```

## Troubleshooting

### Service startet nicht

```bash
# Fehler-Logs anschauen
sudo journalctl -u protonvpn-autoconnect.service -b

# Service manuell starten zum Debuggen
sudo systemctl start protonvpn-autoconnect.service
```

### Credentials funktionieren nicht

1. Stelle sicher, dass du die **OpenVPN/IKEv2 Credentials** verwendest
2. Überprüfe, ob sops die Secrets korrekt entschlüsseln kann:
   ```bash
   sudo cat /run/secrets/protonvpn-username
   sudo cat /run/secrets/protonvpn-password
   ```

### VPN verbindet, aber kein Internet

1. Firewall-Regeln prüfen in `modules/firewall.nix`
2. Stelle sicher, dass `proton0` Interface in der Firewall erlaubt ist (bereits konfiguriert)

### Manuelle Verbindung testen

```bash
# ProtonVPN CLI manuell nutzen
sudo protonvpn-cli c --cc DE -p UDP
sudo protonvpn-cli d  # Disconnect
sudo protonvpn-cli status
```

## Sicherheitshinweise

- ✅ Credentials sind mit sops verschlüsselt
- ✅ Nur root kann Secrets lesen (mode 0400)
- ✅ VPN verbindet VOR dem Login → Kein ungeschützter Traffic
- ✅ Firewall blockiert alles außer VPN (Kill Switch aktiv)
- ✅ Reconnect-Service stellt Verbindung bei Abbruch wieder her

## GUI optional nutzen

Falls du zusätzlich die GUI nutzen möchtest, aktiviere sie in `home-achim.nix`:

```nix
# Zeile 20: Kommentierung entfernen
protonvpn-gui
```

Die CLI-Verbindung läuft unabhängig von der GUI.
