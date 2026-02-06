# Security Procedures & Manual Tasks

Dieses Dokument beschreibt wichtige Sicherheits-Aufgaben, die manuell durchgeführt werden müssen.

## 🔴 Hoch-Priorität Tasks

### 1. Age-Key Backup erstellen

**Warum:** Der Age-Key in `/var/lib/sops-nix/key.txt` ist kritisch für alle verschlüsselten Secrets. Bei Hardware-Defekt sind alle Secrets verloren.

**Schritte:**

```bash
# 1. Age-Key extrahieren und mit Nitrokey GPG-Key verschlüsseln
sudo cat /var/lib/sops-nix/key.txt | \
  gpg --encrypt --recipient $(gpg --list-keys | grep uid | head -1 | awk '{print $NF}') \
  > ~/age-key-backup.gpg

# 2. Backup verifizieren
gpg --decrypt ~/age-key-backup.gpg | head -c 20
# Sollte "AGE-SECRET-KEY-1..." ausgeben

# 3. Backup an sicheren Ort kopieren
# OPTION A: Auf externen USB-Stick (verschlüsselt)
cp ~/age-key-backup.gpg /media/usb-backup/

# OPTION B: Auf Papier drucken (QR-Code)
cat ~/age-key-backup.gpg | qrencode -t UTF8

# 4. Original löschen
shred -uvz ~/age-key-backup.gpg

# 5. Recovery-Test (später, auf anderem System):
# gpg --decrypt age-key-backup.gpg > /var/lib/sops-nix/key.txt
```

**Speicherorte (WÄHLE MINDESTENS 2):**
- ✅ Nitrokey (GPG-verschlüsselt)
- ✅ Offline USB-Stick in Safe
- ✅ Papier-Backup (QR-Code) in Bankschließfach
- ❌ NICHT: Cloud, Email, unverschlüsselt

---

### 2. Swap-Encryption mit Key-File

**Warum:** Aktuell nutzt Swap FIDO2-Entsperrung, was Hibernate/Resume erschwert.

**Schritte:**

```bash
# 1. Keyfile generieren (256-bit Zufallsdaten)
sudo dd if=/dev/random of=/root/crypto_keyfile.bin bs=32 count=1
sudo chmod 000 /root/crypto_keyfile.bin

# 2. Keyfile zu LUKS-Swap hinzufügen
sudo cryptsetup luksAddKey /dev/disk/by-uuid/<swap-uuid> /root/crypto_keyfile.bin
# Aktuelles FIDO2-Passwort eingeben

# 3. NixOS-Konfiguration anpassen
```

**NixOS Config ändern:**
```nix
# In configuration.nix oder hardware-configuration.nix
boot.initrd.luks.devices."luks-swap" = {
  device = "/dev/disk/by-uuid/...";
  keyFile = "/root/crypto_keyfile.bin";
  # FIDO2-Settings entfernen/auskommentieren
};

# Keyfile in initrd einbetten
boot.initrd.secrets = {
  "/crypto_keyfile.bin" = "/root/crypto_keyfile.bin";
};
```

**Nach Rebuild:**
```bash
# 4. Test: Hibernate/Resume sollte ohne FIDO2-Interaktion funktionieren
systemctl hibernate
# Beim Aufwachen: Swap sollte automatisch entsperrt werden

# 5. Alte FIDO2-Slots entfernen (optional)
sudo cryptsetup luksDump /dev/disk/by-uuid/<swap-uuid>
# Slots identifizieren und löschen:
sudo cryptsetup luksKillSlot /dev/disk/by-uuid/<swap-uuid> <slot-number>
```

---

## 🟡 Mittel-Priorität Tasks

### 3. Flatpak Sandbox Härten (Signal Desktop)

**Warum:** Signal via Flatpak läuft in eigener Bubblewrap-Sandbox, aber Defaults sind zu permissiv.

**Schritte:**

```bash
# 1. Aktuelle Permissions prüfen
flatpak info --show-permissions org.signal.Signal

# 2. Unnötige Devices blockieren
flatpak override org.signal.Signal --nodevice=all
flatpak override org.signal.Signal --device=dri  # Nur GPU
flatpak override org.signal.Signal --device=shm  # Shared Memory

# 3. X11 deaktivieren (nur Wayland)
flatpak override org.signal.Signal --nosocket=x11
flatpak override org.signal.Signal --socket=wayland

# 4. Filesystem-Zugriff einschränken
flatpak override org.signal.Signal --nofilesystem=home
flatpak override org.signal.Signal --filesystem=xdg-download:ro  # Nur Downloads lesen
flatpak override org.signal.Signal --filesystem=xdg-pictures:rw  # Bilder senden

# 5. Permissions verifizieren
flatpak override --show org.signal.Signal

# 6. Signal neu starten
flatpak run org.signal.Signal
```

**Erwartetes Ergebnis:**
- ✅ Signal startet und funktioniert
- ✅ Screenshots/Bilder können gesendet werden
- ✅ Downloads sichtbar
- ❌ Kein Zugriff auf gesamtes Home-Verzeichnis

---

### 4. Intel ME Status prüfen

**Warum:** Intel Management Engine kann Backdoor-Risiko darstellen.

**Schritte:**

```bash
# 1. ME-Status prüfen
sudo nix-shell -p intelmetool --run "intelmetool -s"

# Mögliche Ausgaben:
# - ME is disabled: ✅ Gut, nichts tun
# - ME is enabled: ⚠️ Weiter lesen

# 2. ME-Version anzeigen
sudo nix-shell -p intelmetool --run "intelmetool -m"

# 3. Optional: ME deaktivieren mit me_cleaner
# ⚠️ WARNUNG: Kann System unbootbar machen! Backup erstellen!
```

**ME Cleaner (NUR wenn erfahren):**
```bash
# 1. BIOS-Chip-Typ identifizieren
sudo nix-shell -p flashrom --run "flashrom -p internal"

# 2. BIOS-Dump erstellen
sudo flashrom -p internal -r bios_backup.bin

# 3. Backup an 2 verschiedenen Orten speichern!

# 4. ME cleaner ausführen (Dry-run)
nix-shell -p me_cleaner --run "me_cleaner -c bios_backup.bin"

# 5. Wenn OK: Tatsächlich cleanen
# nix-shell -p me_cleaner --run "me_cleaner -S -O bios_cleaned.bin bios_backup.bin"

# 6. Cleaned BIOS flashen
# sudo flashrom -p internal -w bios_cleaned.bin

# ⚠️ NUR bei Erfahrung mit BIOS-Flashing!
```

**Empfehlung:** Wenn ME enabled aber kein Problem verursacht → belassen. Risiko vs. Nutzen abwägen.

---

### 5. Sops Secret-Rotation (90-Tage-Zyklus)

**Warum:** Regelmäßige Rotation reduziert Impact bei Secret-Leak.

**Welche Secrets rotieren:**
- ✅ WLAN-Passwort (alle 6 Monate)
- ✅ E-Mail-Passwort (alle 90 Tage)
- ✅ API-Keys (alle 90 Tage)
- ✅ SSH-Keys (alle 12 Monate)
- ⚠️ ProtonVPN WireGuard Keys (bei Verdacht auf Kompromittierung)

**Schritte:**

```bash
# 1. Sops-Editor öffnen
cd ~/nixos-config
sops secrets/secrets.yaml

# 2. Secrets nacheinander ändern
# - email/posteo/password: <neues-passwort>
# - api/anthropic: <neuer-key>
# - etc.

# 3. Keys re-encrypten (automatisch beim Speichern)

# 4. NixOS rebuilden
sudo nixos-rebuild switch

# 5. Services neu starten (falls nötig)
sudo systemctl restart email-alerts.service

# 6. Funktionstest
curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $(cat /run/secrets/api/anthropic)" | jq .

# 7. Alte Secrets bei Providern deaktivieren
# - Posteo: Altes Passwort ändern
# - Anthropic: Alten API-Key widerrufen
# - GitHub: Alten Token löschen
```

**Rotation-Schedule:**
```bash
# Kalendereintrag erstellen
echo "0 0 1 */3 * /home/user/nixos-config/scripts/rotate-secrets.sh" | crontab -
```

---

### 6. Time-Based Fingerprinting Mitigation

**Warum:** System-Zeit kann für Fingerprinting genutzt werden (Browser, Netzwerk).

**Option A: Tor Time-Synchronization (komplexer)**

```nix
# In configuration.nix
services.tor = {
  enable = true;
  client.enable = true;
};

# Zeit via Tor synchronisieren
systemd.services.tor-time-sync = {
  description = "Synchronize time via Tor";
  after = [ "tor.service" ];
  wants = [ "tor.service" ];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.curl}/bin/curl -x socks5h://localhost:9050 https://www.torproject.org --head | grep Date";
  };
};
```

**Option B: NTS (Network Time Security) - Empfohlen**

```nix
# In configuration.nix
services.chrony = {
  enable = true;
  servers = [
    "time.cloudflare.com nts"
    "nts.netnod.se nts"
  ];
  extraConfig = ''
    # NTS-spezifische Optionen
    ntsdumpdir /var/lib/chrony
    nocerttimecheck 1
  '';
};

# NTP via NixOS deaktivieren
services.timesyncd.enable = false;
```

**Test:**
```bash
# Chrony-Status prüfen
chronyc sources -v
# Sollte "NTS" in der Spalte "Mode" zeigen

# NTS-Keys verifizieren
sudo ls -la /var/lib/chrony/
```

---

## 🔄 Regelmäßige Wartung

### Wöchentlich
- [ ] CVE-Scan-Reports prüfen (`/var/log/cve-scan/`)
- [ ] Suricata-Alerts reviewen (`sudo tail -f /var/log/suricata/fast.log`)
- [ ] Failed SSH-Attempts prüfen (`sudo fail2ban-client status sshd`)

### Monatlich
- [ ] AIDE Integrity-Reports prüfen
- [ ] USBGuard Rules aktualisieren (neue Geräte)
- [ ] Firewall-Logs auswerten (`journalctl -u nftables-firewall`)

### Quartalsweise (90 Tage)
- [ ] Sops Secret-Rotation
- [ ] Secure Boot Keys erneuern (optional)
- [ ] Age-Key Backup-Test (Recovery-Drill)

### Jährlich
- [ ] SSH-Keys neu generieren
- [ ] Kernel-Audit (sicherheitsrelevante Updates)
- [ ] Gesamte Security-Konfiguration reviewen

---

## 📋 Checkliste: Neue Sicherheits-Maßnahme hinzufügen

Wenn du eine neue Security-Feature hinzufügst:

1. [ ] In separatem NixOS-Modul implementieren (`modules/`)
2. [ ] In `configuration.nix` importieren
3. [ ] Build-Test: `nix build .#nixosConfigurations.nixos.config.system.build.toplevel`
4. [ ] Dry-Run: `sudo nixos-rebuild dry-activate`
5. [ ] Commit mit aussagekräftiger Message
6. [ ] Nach Rebuild: Funktionstest durchführen
7. [ ] Monitoring/Alerting einrichten (falls relevant)
8. [ ] Dokumentation aktualisieren (dieses Dokument)

---

## 🆘 Notfall-Prozeduren

### System nicht bootbar nach Security-Change

```bash
# 1. In vorherige Generation booten
# (Beim Bootloader: Ältere Generation wählen)

# 2. Problematische Änderung identifizieren
nixos-rebuild list-generations
git log --oneline -10

# 3. Rollback
sudo nixos-rebuild switch --rollback

# 4. Oder: Spezifische Generation aktivieren
sudo nixos-rebuild switch --generation 42
```

### Secrets verloren (Age-Key weg)

```bash
# 1. Age-Key aus Backup wiederherstellen
gpg --decrypt /media/backup/age-key-backup.gpg | \
  sudo tee /var/lib/sops-nix/key.txt

# 2. Permissions korrigieren
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo chown root:root /var/lib/sops-nix/key.txt

# 3. System rebuilden
sudo nixos-rebuild switch

# 4. Services neu starten
sudo systemctl restart email-alerts sops-nix
```

### LUKS-Entsperrung schlägt fehl

```bash
# 1. Ins Rescue-System booten (USB-Stick)

# 2. LUKS-Status prüfen
cryptsetup luksDump /dev/nvme0n1p2  # Root
cryptsetup luksDump /dev/nvme0n1p3  # Swap

# 3. Mit Backup-Passphrase entsperren
cryptsetup open /dev/nvme0n1p2 luks-root
# Backup-Passphrase (hoffentlich notiert!) eingeben

# 4. Keyfile neu erstellen (siehe oben)
```

---

## 📚 Weiterführende Ressourcen

- [NixOS Security Best Practices](https://nixos.org/manual/nixos/stable/index.html#sec-security)
- [AppArmor Profiling Guide](https://gitlab.com/apparmor/apparmor/-/wikis/Profiling_with_tools)
- [Sops-nix Documentation](https://github.com/Mic92/sops-nix)
- [Kernel Hardening Checklist](https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project/Recommended_Settings)
- [CIS NixOS Benchmark](https://www.cisecurity.org/)

---

**Letzte Aktualisierung:** 2026-02-06
**Version:** 1.0
