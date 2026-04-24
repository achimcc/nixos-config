# Secure Boot Konfiguration mit Lanzaboote
# Signiert Kernel und Initrd für UEFI Secure Boot

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # LANZABOOTE KONFIGURATION
  # ==========================================

  boot.lanzaboote = {
    enable = true;
    # Pfad zu den Secure Boot Keys (von sbctl generiert)
    pkiBundle = "/etc/secureboot";
  };

  # ==========================================
  # SYSTEMD-BOOT DEAKTIVIEREN
  # ==========================================

  # Lanzaboote ersetzt systemd-boot komplett
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # ==========================================
  # SBCTL TOOL
  # ==========================================

  # Tool zur Verwaltung der Secure Boot Keys
  environment.systemPackages = with pkgs; [
    sbctl
  ];

  # ==========================================
  # SECURE BOOT MONITORING
  # ==========================================

  # Systemd-Service zur Verifikation, ob Secure Boot aktiv ist
  systemd.services.verify-secureboot = {
    description = "Verify Secure Boot Status";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Prüfe ob Secure Boot aktiviert ist
      if ! ${pkgs.sbctl}/bin/sbctl status | grep -q "Secure Boot.*enabled"; then
        # Desktop-Benachrichtigung für User
        sudo -u user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
          ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=dialog-error \
          "Secure Boot WARNUNG" "Secure Boot ist NICHT aktiviert! System ist ungeschützt." || true

        # System-Log
        echo "WARNING: Secure Boot is NOT enabled!" | ${pkgs.systemd}/bin/systemd-cat -t secureboot -p err
      else
        echo "Secure Boot is enabled and active." | ${pkgs.systemd}/bin/systemd-cat -t secureboot -p info
      fi
    '';
  };

  # ==========================================
  # TPM 2.0 INTEGRATION
  # ==========================================
  #
  # TPM2-Support ist aktiviert via boot.initrd.systemd.tpm2.enable in configuration.nix
  #
  # LUKS-Entsperrung Hierarchie (nach TPM-Enrollment):
  # 1. TPM2 (automatisch, falls PCRs übereinstimmen)
  # 2. FIDO2 (Nitrokey 3C NFC + PIN + Touch)
  # 3. Passphrase (Fallback)
  #
  # PCR-POLICY: 0+7+11
  # - PCR 0:  UEFI-Firmware
  # - PCR 7:  Secure Boot State (db/dbx/PK/KEK)
  # - PCR 11: Lanzaboote UKI-Measurement (Kernel+Initrd+Cmdline)
  # → Angreifer mit physischem Zugriff kann keinen manipulierten Kernel booten.
  #
  # TPM2-LUKS ENROLLMENT (manueller Schritt, einmalig):
  #
  # 1. Alte Enrollments (0+7) entfernen:
  #    sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
  #    sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
  #
  # 2. Neu enrollen mit 0+7+11:
  #    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7+11 /dev/nvme0n1p2
  #    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7+11 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
  #
  # 3. Reboot testen. Bei Fehlschlag: FIDO2 oder Passphrase-Fallback nutzen.
  #
  # WICHTIG:
  # - PCR 11 ändert sich bei jedem Kernel/Initrd-Update → `tpm2-reenroll`-Service
  #   erneuert das Enrollment automatisch nach Rebuild (siehe unten).
  # - Bei sbctl-Key-Rotation (PCR 7 ändert sich) ebenfalls re-enrollen.
  # - FUTURE: Public-Key-Policy (--tpm2-public-key + signed UKI) würde Re-Enroll
  #   überflüssig machen, aber Lanzaboote signiert UKI-PCR-Werte aktuell nicht.
  #
  # Vollständige Anleitung: docs/TPM-ENROLLMENT.md

  # ==========================================
  # TPM2 AUTOMATISCHES RE-ENROLLMENT
  # ==========================================
  # PCR 11 ändert sich bei jedem Kernel/Initrd-Update (neues UKI).
  # Ohne Re-Enroll würde TPM beim nächsten Boot die Entsperrung verweigern
  # → User fällt auf FIDO2/Passphrase zurück (funktioniert, aber nervig).
  #
  # Dieser Service läuft NACH nixos-rebuild switch und prüft ob die aktuellen
  # PCR-Werte mit dem gespeicherten Enrollment übereinstimmen. Wenn nicht:
  # Re-Enrollment mit aktuellen Werten.
  #
  # Security-Note: Re-Enrollment passiert WÄHREND das System läuft (nach
  # erfolgreichem Boot mit alten Werten). Das ist vom Trust-Model her OK —
  # ein Angreifer der den Rebuild auslösen kann, kontrolliert den Host eh.
  systemd.services.tpm2-reenroll = {
    description = "Re-enroll TPM2 LUKS slots after kernel/initrd update (PCR 11)";
    # Läuft bei jedem Boot, vergleicht PCR 11 gegen gespeicherten Stand
    # und re-enrollt nur wenn sich der Wert geändert hat (= neuer Kernel/Initrd).
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Markiere erfolgreich auch bei Exit 1 (TPM2 nicht verfügbar, FIDO2-only etc.)
      SuccessExitStatus = "0 1";
    };

    script = ''
      set -eu
      STATE_DIR="/var/lib/tpm2-reenroll"
      mkdir -p "$STATE_DIR"
      chmod 0700 "$STATE_DIR"

      # Aktuellen PCR-11-Wert ermitteln (hex sha256)
      CURRENT_PCR11=$(${pkgs.tpm2-tools}/bin/tpm2_pcrread sha256:11 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -oE '0x[0-9a-fA-F]+' | head -1 || echo "")

      if [ -z "$CURRENT_PCR11" ]; then
        echo "tpm2-reenroll: TPM2 nicht lesbar, skip"
        exit 1
      fi

      # Letzten gesehenen PCR 11 vergleichen
      LAST_FILE="$STATE_DIR/last-pcr11"
      if [ -f "$LAST_FILE" ] && [ "$(cat "$LAST_FILE")" = "$CURRENT_PCR11" ]; then
        echo "tpm2-reenroll: PCR 11 unverändert, kein Re-Enroll nötig"
        exit 0
      fi

      echo "tpm2-reenroll: PCR 11 hat sich geändert (neuer Kernel/Initrd)"
      echo "  Neu: $CURRENT_PCR11"

      # Re-Enrollment für beide LUKS-Devices.
      # --wipe-slot=tpm2 entfernt alten Slot, --tpm2-pcrs=0+7+11 enrollt neu.
      # Root-Partition:
      ROOT_DEV="/dev/disk/by-uuid/fcef0557-8a09-4f30-b78e-aecc458a975a"
      SWAP_DEV="/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b"

      for DEV in "$ROOT_DEV" "$SWAP_DEV"; do
        if [ ! -e "$DEV" ]; then
          echo "  ⚠ $DEV existiert nicht, skip"
          continue
        fi
        echo "  Re-enroll $DEV..."
        ${pkgs.systemd}/bin/systemd-cryptenroll --wipe-slot=tpm2 "$DEV" 2>/dev/null || true
        if ${pkgs.systemd}/bin/systemd-cryptenroll \
             --tpm2-device=auto \
             --tpm2-pcrs=0+7+11 \
             "$DEV"; then
          echo "  ✓ Re-enroll erfolgreich: $DEV"
        else
          echo "  ⚠ Re-enroll FEHLGESCHLAGEN: $DEV (FIDO2/Passphrase-Fallback weiterhin aktiv)"
        fi
      done

      echo "$CURRENT_PCR11" > "$LAST_FILE"
      echo "tpm2-reenroll: Fertig"
    '';
  };
}
