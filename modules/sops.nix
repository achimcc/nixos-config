# Sops-nix Secret Management
# Verschlüsselte Secrets im Git Repository

{ config, lib, pkgs, id, ... }:

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

    # WireGuard-Schlüssel der neun VPN-Slots (wireguard/slot1…9) werden in
    # modules/vpn.nix deklariert — dort, wo auch das NM-Template entsteht.

    # WLAN Passwort
    secrets."wifi/home" = {};
    # Flint-Router (WPA3), derselbe Wert wie wlan-vertraut in homeserver-secrets
    secrets."wifi/rusty" = {};

    # E-Mail Passwort für Posteo
    secrets."email/posteo" = {
      owner = id.username;
      mode = "0400";
    };

    # Anthropic API Key für AI Tools (avante.nvim, etc.)
    secrets."anthropic-api-key" = {
      owner = id.username;
      mode = "0400";
    };

    # GitHub Token für gh CLI und octo.nvim
    secrets."github-token" = {
      owner = id.username;
      mode = "0400";
    };

    # SSH Key für Hetzner VPS
    secrets."ssh/hetzner-vps" = {
      owner = id.username;
      mode = "0600";
      path = "/home/${id.username}/.ssh/hetzner-vps";
    };
    secrets."ssh/hetzner-vps-pub" = {
      owner = id.username;
      mode = "0644";
      path = "/home/${id.username}/.ssh/hetzner-vps.pub";
    };

    # Miniflux RSS-Reader Zugangsdaten
    secrets."miniflux/url" = {
      owner = id.username;
      mode = "0400";
    };
    secrets."miniflux/username" = {
      owner = id.username;
      mode = "0400";
    };
    secrets."miniflux/password" = {
      owner = id.username;
      mode = "0400";
    };

    # FIDO2-Zuordnung für pam_u2f: Credential-Handle und öffentlicher Schlüssel
    # des Nitrokey 3, erzeugt mit `pamu2fcfg -u <benutzer> -N`.
    #
    # Warum hier und nicht in ~/.config/Yubico/u2f_keys (dem Standardpfad):
    # 1. Das Repo ist öffentlich — die Zeile enthält den Benutzernamen.
    # 2. Root-eigen und 0400: Eine Datei, die der Benutzer selbst schreiben
    #    könnte, hiesse er könnte sich für sudo einen eigenen Schlüssel
    #    eintragen. Der Weg über /run/secrets schliesst das aus.
    #
    # Fällt sops-nix aus, fehlt die Datei, pam_u2f schlägt fehl und der Stack
    # fragt das Passwort — der Rückfallweg bleibt also intakt.
    secrets."u2f/mappings" = {
      owner = "root";
      mode = "0400";
    };

    # Template für NetworkManager Environment-Datei
    templates."nm-wifi-env" = {
      content = ''
        WIFI_HOME_PSK=${config.sops.placeholder."wifi/home"}
        WIFI_RUSTY_PSK=${config.sops.placeholder."wifi/rusty"}
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
