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

    # Age Key für Entschlüsselung
    age = {
      # Kein SSH Key vorhanden, nur Age Key nutzen
      sshKeyPaths = [];
      # Age Key Datei (wird von generateKey erstellt)
      keyFile = "/var/lib/sops-nix/key.txt";
      # Key generieren falls nicht vorhanden
      generateKey = true;
    };

    # ==========================================
    # SECRETS DEFINITIONEN
    # ==========================================

    # WireGuard Private Key für ProtonVPN (wird in protonvpn.nix referenziert)
    # Die alten protonvpn-username/password werden nicht mehr benötigt
    # da WireGuard statt protonvpn-cli verwendet wird

    # WLAN Passwort
    secrets."wifi/home" = {};

    # E-Mail Passwort für Posteo
    secrets."email/posteo" = {
      owner = "achim";
      mode = "0400";
    };

    # Anthropic API Key für AI Tools (avante.nvim, etc.)
    secrets."anthropic-api-key" = {
      owner = "achim";
      mode = "0400";
    };

    # Template für NetworkManager Environment-Datei
    templates."nm-wifi-env" = {
      content = ''
        WIFI_HOME_PSK=${config.sops.placeholder."wifi/home"}
      '';
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
