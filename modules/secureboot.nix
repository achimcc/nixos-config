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
  # TPM2-LUKS ENROLLMENT (manueller Schritt nach Reboot):
  #
  # 1. Root-Partition mit TPM2 verbinden:
  #    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
  #
  # 2. Swap-Partition mit TPM2 verbinden:
  #    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
  #
  # PCR Bindings Erklärung:
  # - PCR 0: Firmware (UEFI)
  # - PCR 7: Secure Boot State
  #
  # Wichtig: Bei Secure Boot Key-Änderungen (z.B. sbctl rotate) müssen
  # die TPM2-Enrollments erneuert werden, da PCR 7 sich ändert.
  #
  # Vollständige Anleitung: docs/TPM-ENROLLMENT.md
}
