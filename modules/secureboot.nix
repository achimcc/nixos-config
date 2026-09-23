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

  # Systemd-Service zur Verifikation, ob Secure Boot aktiv ist.
  # Er schreibt NUR ins Journal. Die Desktop-Meldung kommt vom Nutzerdienst
  # `secureboot-warnung` (home.nix): Zur Zeit von multi-user.target gibt es
  # noch keine Sitzung und keinen Session-Bus. Bis 2026-09-23 stand hier
  # `sudo -u …` — sudo gibt es im Unit-PATH nicht ("sudo: command not found",
  # gemessen im Journal), die Meldung kam nie, die Unit meldete Erfolg.
  #
  # Gelesen wird die Firmware-Variable, nicht `sbctl status`: Dessen Text
  # ändert sich („old configuration detected") und braucht die PKI unter
  # /etc/secureboot. Byte 5 der Variable (nach 4 Attribut-Bytes) ist 1 = an.
  systemd.services.verify-secureboot = {
    description = "Verify Secure Boot Status";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      SB_VAR=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
      SB_STATE=$(${pkgs.coreutils}/bin/od -An -tu1 -j4 -N1 "$SB_VAR" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d ' ')
      SB_STATE=''${SB_STATE:-unbekannt}
      if [ "$SB_STATE" != "1" ]; then
        echo "WARNING: Secure Boot is NOT enabled (efivar SecureBoot=$SB_STATE)" \
          | ${pkgs.systemd}/bin/systemd-cat -t secureboot -p err
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
