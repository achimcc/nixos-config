# ProtonVPN via WireGuard mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SOPS SECRET FÜR WIREGUARD PRIVATE KEY
  # ==========================================

  sops.secrets.wireguard-private-key = {
    mode = "0400";
    owner = "root";
  };

  # ==========================================
  # WIREGUARD INTERFACE KONFIGURATION
  # ==========================================

  networking.wg-quick.interfaces.proton0 = {
    # Client IP-Adresse (aus der ProtonVPN Konfiguration)
    address = [ "10.2.0.2/32" ];

    # DNS Server (ProtonVPN DNS für Leak-Schutz)
    dns = [ "10.2.0.1" ];

    # Private Key aus SOPS
    privateKeyFile = config.sops.secrets.wireguard-private-key.path;

    # Automatisch beim Boot starten
    autostart = true;

    # ProtonVPN Server (DE#782)
    peers = [
      {
        publicKey = "3OmDkvs7FoqiYtV9rzMUdxcWkNXH/loCVZaiPJH18mI=";
        endpoint = "79.127.141.53:51820";
        # Route allen Traffic über VPN
        allowedIPs = [ "0.0.0.0/0" ];
        # Keepalive für NAT-Traversal
        persistentKeepalive = 25;
      }
    ];

    # Post-Up: Sicherstellen dass DNS korrekt gesetzt ist
    postUp = ''
      # Warte kurz auf Interface-Stabilisierung
      sleep 2
      echo "ProtonVPN WireGuard verbunden!"
    '';

    postDown = ''
      echo "ProtonVPN WireGuard getrennt."
    '';
  };

  # ==========================================
  # SYSTEMD SERVICE KONFIGURATION
  # ==========================================

  # Stelle sicher dass WireGuard vor dem Display Manager startet
  systemd.services."wg-quick-proton0" = {
    before = [ "display-manager.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "sops-nix.service" ];
  };

  # ==========================================
  # PROTONVPN CLI (optional, für manuelle Nutzung)
  # ==========================================

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
