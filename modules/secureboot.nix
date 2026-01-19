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
}
