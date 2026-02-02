# TPM 2.0 LUKS Enrollment Anleitung

## Übersicht

Diese Anleitung beschreibt, wie man TPM 2.0 für die automatische LUKS-Entsperrung beim Boot einrichtet. Nach dem Enrollment entsperrt das System die verschlüsselten Partitionen automatisch, solange die gemessenen PCR-Werte übereinstimmen.

## Voraussetzungen

- TPM 2.0 Hardware muss vorhanden sein (`ls -l /dev/tpm*`)
- `boot.initrd.systemd.tpm2.enable = true` in configuration.nix
- System wurde mit der neuen Konfiguration neu gebaut und gebootet
- Bestehende FIDO2-Entsperrung funktioniert

## Unlock-Hierarchie nach TPM-Enrollment

1. **TPM2** (automatisch, falls PCRs übereinstimmen)
2. **FIDO2** (Nitrokey 3C NFC + PIN + Touch)
3. **Passphrase** (Fallback)

## Enrollment-Schritte

### 1. TPM2-Device verifizieren

```bash
# TPM Device prüfen
ls -l /dev/tpm*
# Sollte /dev/tpm0 und /dev/tpmrm0 zeigen

# TPM-Status prüfen (optional)
sudo systemd-cryptenroll --tpm2-device=list
```

### 2. Root-Partition enrollen

```bash
# Root-Partition (anpassen an deine UUID)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

**Wichtig:** Du wirst nach deinem LUKS-Passwort gefragt!

### 3. Swap-Partition enrollen

```bash
# Swap-Partition (anpassen an deine UUID)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
```

### 4. Enrollment verifizieren

```bash
# Root-Partition prüfen
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep -A5 "systemd-tpm2"

# Swap-Partition prüfen
sudo cryptsetup luksDump /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b | grep -A5 "systemd-tpm2"
```

Du solltest einen Token-Slot mit "systemd-tpm2" sehen.

### 5. System neu starten

```bash
sudo reboot
```

Beim nächsten Boot sollte das System automatisch entsperren (kein FIDO2-Touch nötig).

## PCR Bindings Erklärung

Die PCRs (Platform Configuration Registers) speichern Hash-Messungen verschiedener Boot-Komponenten:

- **PCR 0**: UEFI Firmware
- **PCR 7**: Secure Boot State (inkl. verwendete Keys)

### Wann ändern sich PCRs?

- **PCR 0**: Firmware-Updates
- **PCR 7**: Secure Boot Key-Änderungen (z.B. `sbctl rotate`)

**Wichtig:** Nach Änderungen an Secure Boot Keys müssen die TPM2-Enrollments erneuert werden!

## Troubleshooting

### TPM-Entsperrung funktioniert nicht

1. **PCRs haben sich geändert** (z.B. nach Firmware-Update oder Secure Boot Key-Rotation)
   - System fällt automatisch auf FIDO2 zurück
   - Nach erfolgreichem Boot TPM2-Enrollment erneuern

2. **TPM2-Enrollment erneuern:**

```bash
# Altes TPM2-Token entfernen
sudo systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=tpm2

# Neues TPM2-Token hinzufügen
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2

# Gleiches für Swap wiederholen
sudo systemd-cryptenroll /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b --wipe-slot=tpm2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
```

### Alle TPM2-Tokens entfernen (Rollback)

Falls du TPM2 nicht mehr verwenden möchtest:

```bash
# Root
sudo systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=tpm2

# Swap
sudo systemd-cryptenroll /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b --wipe-slot=tpm2
```

System bootet dann wieder mit FIDO2 + Passphrase.

## Sicherheitshinweise

1. **FIDO2 bleibt primäre Authentifizierung**: TPM2 ist nur ein Komfort-Feature
2. **Passphrase-Fallback beibehalten**: Niemals alle Unlock-Methoden außer TPM2 entfernen
3. **Regelmäßige Verifikation**: Nach System-Updates prüfen, ob TPM2-Unlock noch funktioniert
4. **PCR-Bindings dokumentieren**: Merke dir, welche PCRs du verwendest (0+7)

## Weitere Informationen

- [systemd-cryptenroll man page](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html)
- [Arch Wiki: TPM](https://wiki.archlinux.org/title/Trusted_Platform_Module)
