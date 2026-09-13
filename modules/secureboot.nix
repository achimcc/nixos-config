# Secure Boot Konfiguration mit Lanzaboote
# Signiert Kernel und Initrd für UEFI Secure Boot

{ config, lib, pkgs, id, ... }:

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
        sudo -u ${id.username} DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
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
  # TPM 2.0 UND LUKS
  # ==========================================
  #
  # Seit 2026-09-13 entsperrt TPM2 KEIN LUKS-Gerät mehr. Root und Swap
  # öffnen sich per FIDO2 (Nitrokey 3, PIN + Berührung) oder Passphrase,
  # siehe die LUKS-Blöcke in configuration.nix.
  #
  # Der frühere Dienst `tpm2-reenroll` ist deshalb entfernt. Er trug nach
  # jedem Kernel-Update (PCR 11) die TPM2-Slots neu ein, löschte dabei zuerst
  # den alten Slot und hing dann an einer Passphrase-Abfrage, die im
  # Dienstkontext niemand beantwortet. Käme er zurück, legte er an der
  # Root-Partition stillschweigend wieder einen TPM2-Slot an.
  #
  # Vollständig: docs/superpowers/plans/2026-09-12-nitrokey-fido2.md
}
