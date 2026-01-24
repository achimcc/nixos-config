# ProtonVPN via WireGuard mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops (Private Key, Endpoint, PublicKey)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SOPS SECRETS FÜR WIREGUARD
  # ==========================================

  sops.secrets.wireguard-private-key = {
    mode = "0400";
    owner = "root";
  };

  # Endpoint und PublicKey werden in sops.nix definiert
  # und über das Template wireguard-proton0.conf bereitgestellt

  # ==========================================
  # WIREGUARD VERZEICHNIS
  # ==========================================

  # Stelle sicher, dass das WireGuard-Verzeichnis existiert
  systemd.tmpfiles.rules = [
    "d /etc/wireguard 0700 root root -"
  ];

  # ==========================================
  # SYSTEMD SERVICE FÜR WIREGUARD
  # ==========================================

  # Eigener Service, der die sops-generierte Konfigurationsdatei verwendet
  systemd.services."wg-quick-proton0" = {
    description = "WireGuard VPN - ProtonVPN";

    # Starte nach Netzwerk und sops
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # Vor dem Display Manager starten
    before = [ "display-manager.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Starte WireGuard mit der sops-generierten Konfiguration
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${config.sops.templates."wireguard-proton0.conf".path}";
      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${config.sops.templates."wireguard-proton0.conf".path}";

      # Neustart bei Fehlern
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Post-Up Logging
    postStart = ''
      sleep 2
      echo "ProtonVPN WireGuard verbunden!"
    '';
  };

  # ==========================================
  # WIREGUARD TOOLS
  # ==========================================

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
