# GPG-Nitrokey Integration für Thunderbird in Firejail

**Datum:** 2026-02-03
**Status:** Design abgeschlossen, bereit für Implementation

## Übersicht

Konfiguration von Thunderbird (in Firejail-Sandbox) zur Nutzung von GPG-Verschlüsselung mit Nitrokey 3C NFC für E-Mail-Verschlüsselung.

## Architektur

### Komponenten und Datenfluss

```
Thunderbird (Firejail)
    ↓ (Socket: /run/user/1000/gnupg/S.gpg-agent)
GPG-Agent (User Service)
    ↓ (USB HID)
Nitrokey 3C NFC
```

### Bestehende Infrastruktur

**Bereits konfiguriert:**
- ✅ Nitrokey 3C NFC Support (`hardware.nitrokey.enable = true`)
- ✅ GPG-Agent mit pinentry-gnome3
- ✅ GPG-Schlüssel auf Nitrokey (<mail>)
- ✅ Firejail GPG-Agent Socket Zugriff (`/run/user/1000/gnupg`)
- ✅ Firejail Nitrokey-Zugriff (`ignore private-dev`, `ignore nou2f`)

**Noch zu konfigurieren:**
- ❌ Thunderbird externe GnuPG-Nutzung
- ❌ Öffentlicher Schlüssel-Export für Thunderbird
- ❌ Firejail-Zugriff auf Key-Export-Ordner

## Design-Entscheidungen

### 1. Externes GnuPG vs. Thunderbird-internes OpenPGP

**Entscheidung:** Externes GnuPG nutzen

**Begründung:**
- Private Schlüssel bleiben auf Nitrokey (höhere Sicherheit)
- Nutzt vorhandene GPG-Infrastruktur
- Konsistent mit sonstiger GPG-Nutzung am System

### 2. Deklarative vs. manuelle Konfiguration

**Entscheidung:** Deklarativ via user.js

**Begründung:**
- Passt zur NixOS-Philosophie
- Versioniert in Git
- Reproduzierbar bei System-Rebuilds
- Robuster gegen versehentliches Zurücksetzen

### 3. Key-Export-Strategie

**Entscheidung:** Dedizierter Ordner `~/.config/thunderbird-gpg/`

**Begründung:**
- Sauberer als ~/Downloads
- Kein manuelles Cleanup nötig
- Explizite Firejail-Whitelist
- Wiederverwendbar für zukünftige Keys

## Implementation

### Schritt 1: Thunderbird user.js Konfiguration

**Datei:** `home.nix`

**Konfiguration:**
```nix
home.file.".thunderbird/<nutzer>/user.js".text = ''
  // Externes GnuPG aktivieren
  user_pref("mail.openpgp.allow_external_gnupg", true);

  // GPG-Binary explizit setzen
  user_pref("mail.openpgp.gnupg_path", "/run/current-system/sw/bin/gpg");

  // Schlüssel aus GnuPG importieren
  user_pref("mail.openpgp.fetch_pubkeys_from_gnupg", true);
'';
```

**Effekt:**
- Thunderbird nutzt System-GPG statt internes OpenPGP
- GPG-Agent-Kommunikation wird aktiviert
- Öffentliche Schlüssel werden aus GPG-Keyring geladen

### Schritt 2: GPG Public Key Export Service

**Datei:** `home.nix`

**Systemd User Service:**
```nix
systemd.user.services.export-gpg-pubkey = {
  Unit = {
    Description = "Export GPG public key for Thunderbird";
  };
  Service = {
    Type = "oneshot";
    ExecStart = pkgs.writeShellScript "export-gpg-key" ''
      mkdir -p ~/.config/thunderbird-gpg
      ${pkgs.gnupg}/bin/gpg --armor --export <mail> \
        -o ~/.config/thunderbird-gpg/gpg-public-key.asc
    '';
  };
  Install = {
    WantedBy = [ "default.target" ];
  };
};
```

**Effekt:**
- Öffentlicher Schlüssel wird beim Login exportiert
- Liegt in `~/.config/thunderbird-gpg/gpg-public-key.asc`
- Bereit für Import in Thunderbird

### Schritt 3: Firejail Konfiguration erweitern

**Datei:** `modules/network.nix`

**Erweiterung von `environment.etc."firejail/thunderbird.local"`:**
```nix
# GPG Public Key Import (dedizierter Ordner für Key-Austausch)
noblacklist ${HOME}/.config/thunderbird-gpg
whitelist ${HOME}/.config/thunderbird-gpg
```

**Effekt:**
- Thunderbird kann auf `~/.config/thunderbird-gpg/` zugreifen
- Öffentlicher Schlüssel ist in der Sandbox sichtbar

## Testing und Verifikation

### 1. System-Rebuild
```bash
sudo nixos-rebuild switch --flake /home/<nutzer>/nixos-config#nixos
```

### 2. GPG-Agent Kommunikation testen
```bash
# Thunderbird-Firejail-Umgebung testen
firejail --profile=/etc/firejail/thunderbird.profile gpg --card-status
```

**Erwartung:** Nitrokey wird erkannt, Schlüssel-Info angezeigt

### 3. Thunderbird user.js verifizieren
```bash
# Nach Thunderbird-Start
grep "allow_external_gnupg" ~/.thunderbird/*/prefs.js
```

**Erwartung:** `user_pref("mail.openpgp.allow_external_gnupg", true);`

### 4. Öffentlicher Schlüssel verfügbar
```bash
ls -la ~/.config/thunderbird-gpg/gpg-public-key.asc
cat ~/.config/thunderbird-gpg/gpg-public-key.asc
```

**Erwartung:** ASCII-armored GPG public key

### 5. Manueller Import in Thunderbird

**Schritte:**
1. Thunderbird öffnen
2. Account Settings → End-to-End Encryption
3. Add Key → Import
4. Datei wählen: `~/.config/thunderbird-gpg/gpg-public-key.asc`
5. Key für <mail> akzeptieren

### 6. E-Mail Signierung testen

**Schritte:**
1. Neue E-Mail verfassen
2. Options → Digitally Sign aktivieren
3. E-Mail senden

**Erwartung:**
- Pinentry-Dialog für Smartcard-PIN
- Nitrokey-Touch-Aufforderung
- E-Mail wird signiert

### 7. E-Mail Verschlüsselung testen

**Schritte:**
1. E-Mail an <mail> (sich selbst) senden
2. Encrypt aktivieren
3. Verschlüsselte E-Mail empfangen und öffnen

**Erwartung:**
- Nitrokey-Touch für Entschlüsselung
- E-Mail-Inhalt wird entschlüsselt angezeigt

## Troubleshooting

### GPG-Agent läuft nicht
```bash
# Status prüfen
systemctl --user status gpg-agent

# Neustart
gpgconf --kill gpg-agent
systemctl --user restart gpg-agent
```

### Thunderbird sieht GPG nicht
```bash
# Firejail-Debug-Modus
firejail --debug thunderbird

# GPG-Socket-Zugriff prüfen
ls -la /run/user/1000/gnupg/
```

### Nitrokey wird nicht erkannt
```bash
# Kartenstatus prüfen
gpg --card-status

# USB-Geräte prüfen
lsusb | grep -i nitrokey

# Firejail /dev/hidraw* Zugriff prüfen
firejail --profile=/etc/firejail/thunderbird.profile ls -la /dev/hidraw*
```

### Export-Service läuft nicht
```bash
# Service-Status
systemctl --user status export-gpg-pubkey

# Manuell ausführen
systemctl --user start export-gpg-pubkey

# Logs anzeigen
journalctl --user -u export-gpg-pubkey
```

## Sicherheitsaspekte

### Private Schlüssel bleiben sicher
- Private Keys verlassen den Nitrokey nie
- Nur öffentlicher Schlüssel wird exportiert
- GPG-Agent-Kommunikation über Unix-Socket (lokal)

### Firejail-Isolation bleibt intakt
- Minimale Whitelists (nur GPG-Socket und Key-Export-Ordner)
- Keine zusätzlichen Netzwerk- oder Dateisystem-Zugriffe
- GNOME Keyring für Posteo-Passwort (bestehende Konfiguration)

### PIN-Schutz
- Smartcard-PIN wird via pinentry-gnome3 abgefragt
- Cache TTL: 8 Stunden (28800 Sekunden)
- `grab` verhindert Keylogging während PIN-Eingabe

## Weitere Schritte (nach Implementation)

1. Öffentlichen Schlüssel auf Keyserver hochladen (optional)
   ```bash
   gpg --send-keys 0x91D349BAE4FC508E
   ```

2. Schlüssel-Fingerprint in E-Mail-Signatur hinzufügen (optional)

3. Kontakten öffentlichen Schlüssel mitteilen für verschlüsselte Kommunikation

4. Backup-Strategie für GPG-Keys dokumentieren
