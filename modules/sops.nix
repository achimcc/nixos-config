# Sops-nix Secret Management
# Verschlüsselte Secrets im Git Repository

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SOPS GRUNDKONFIGURATION
  # ==========================================

  sops = {
    # Standard Secrets-Datei
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    # Age Key aus SSH Host Key ableiten
    age = {
      # SSH Host Key wird automatisch zu Age Key konvertiert
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      # Alternativ: Eigener Age Key
      keyFile = "/var/lib/sops-nix/key.txt";
      # Key generieren falls nicht vorhanden
      generateKey = true;
    };

    # ==========================================
    # SECRETS DEFINITIONEN
    # ==========================================

    # Beispiel: API Keys, Passwörter, etc.
    # Diese werden nach /run/secrets/<name> entschlüsselt

    # WLAN Passwort (raw value)
    secrets."wifi/home" = {};

    # Template für wpa_supplicant Secrets-Datei
    templates."wpa_supplicant.conf" = {
      content = ''
        wifi_home_psk=${config.sops.placeholder."wifi/home"}
      '';
      # Muss vor wpa_supplicant Service verfügbar sein
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # Sops CLI Tool verfügbar machen
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
