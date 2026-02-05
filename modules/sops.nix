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

    # GitHub Token für gh CLI und octo.nvim
    secrets."github-token" = {
      owner = "achim";
      mode = "0400";
    };

    # ProtonVPN WireGuard Konfiguration
    secrets."protonvpn/endpoint" = {
      owner = "root";
      mode = "0400";
    };
    secrets."protonvpn/publickey" = {
      owner = "root";
      mode = "0400";
    };

    # SSH Key für Hetzner VPS
    secrets."ssh/hetzner-vps" = {
      owner = "achim";
      mode = "0600";
      path = "/home/achim/.ssh/hetzner-vps";
    };
    secrets."ssh/hetzner-vps-pub" = {
      owner = "achim";
      mode = "0644";
      path = "/home/achim/.ssh/hetzner-vps.pub";
    };

    # Miniflux RSS-Reader Zugangsdaten
    secrets."miniflux/url" = {
      owner = "achim";
      mode = "0400";
    };
    secrets."miniflux/username" = {
      owner = "achim";
      mode = "0400";
    };
    secrets."miniflux/password" = {
      owner = "achim";
      mode = "0400";
    };

    # ProtonVPN IP-Ranges (verschleiert Verwendung von ProtonVPN)
    # TODO: Aktiviere nach Hinzufügen in secrets.yaml (siehe docs/TODO-SOPS-PROTONVPN.md)
    # secrets."protonvpn/ip-ranges" = {
    #   owner = "root";
    #   mode = "0400";
    # };

    # Template für NetworkManager Environment-Datei
    templates."nm-wifi-env" = {
      content = ''
        WIFI_HOME_PSK=${config.sops.placeholder."wifi/home"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # WireGuard Konfigurationsdatei für ProtonVPN (aus Secrets generiert)
    templates."wireguard-proton0.conf" = {
      content = ''
        [Interface]
        PrivateKey = ${config.sops.placeholder."wireguard-private-key"}
        Address = 10.2.0.2/32
        # Table = 51820 statt "auto" vermeidet iptables-restore (nftables-Konflikt)
        # Policy routing rules are handled in systemd service ExecStartPost
        Table = 51820

        [Peer]
        PublicKey = ${config.sops.placeholder."protonvpn/publickey"}
        Endpoint = ${config.sops.placeholder."protonvpn/endpoint"}
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
      '';
      path = "/etc/wireguard/proton0.conf";
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  # Sops CLI Tool verfügbar machen
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
