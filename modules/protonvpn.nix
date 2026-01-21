# ProtonVPN CLI mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # PROTONVPN CLI INSTALLATION
  # ==========================================

  environment.systemPackages = with pkgs; [
    protonvpn-cli
  ];

  # ==========================================
  # SECRETS FÜR PROTONVPN CREDENTIALS
  # ==========================================

  sops.secrets.protonvpn-username = {
    mode = "0400";
    owner = "root";
  };

  sops.secrets.protonvpn-password = {
    mode = "0400";
    owner = "root";
  };

  # ==========================================
  # SYSTEMD SERVICE FÜR AUTO-CONNECT
  # ==========================================

  systemd.services.protonvpn-autoconnect = {
    description = "ProtonVPN Automatic Connection";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "display-manager.service" ]; # Startet VOR dem Login-Screen
    wantedBy = [ "multi-user.target" ];

    # Service erst starten wenn Netzwerk wirklich verfügbar ist
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5"; # Warte kurz auf Netzwerk-Stabilisierung

      # Login Script: Liest Credentials aus sops und führt Login durch
      ExecStart = pkgs.writeShellScript "protonvpn-connect" ''
        set -e

        # Credentials aus sops-entschlüsselten Files laden
        USERNAME=$(cat ${config.sops.secrets.protonvpn-username.path})
        PASSWORD=$(cat ${config.sops.secrets.protonvpn-password.path})

        # ProtonVPN initialisieren falls nötig
        if [ ! -f /root/.pvpn-cli/pvpn-cli.cfg ]; then
          echo "Initialisiere ProtonVPN CLI..."
          echo -e "$USERNAME\n$PASSWORD" | ${pkgs.protonvpn-cli}/bin/protonvpn-cli login
        fi

        # Mit schnellstem deutschen Server verbinden
        echo "Verbinde mit ProtonVPN..."
        ${pkgs.protonvpn-cli}/bin/protonvpn-cli c --cc DE -p UDP

        echo "ProtonVPN erfolgreich verbunden!"
      '';

      # Beim Shutdown: Saubere Trennung
      ExecStop = "${pkgs.protonvpn-cli}/bin/protonvpn-cli d";

      # Hardening
      PrivateTmp = true;
      NoNewPrivileges = true;

      # Restart bei Fehler
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # ==========================================
  # SYSTEMD SERVICE FÜR RECONNECT
  # ==========================================

  # Falls VPN-Verbindung abbricht, automatisch neu verbinden
  systemd.services.protonvpn-reconnect = {
    description = "ProtonVPN Reconnect Service";
    after = [ "protonvpn-autoconnect.service" ];
    requires = [ "protonvpn-autoconnect.service" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "30s";

      # Überwacht VPN-Verbindung und reconnected bei Bedarf
      ExecStart = pkgs.writeShellScript "protonvpn-monitor" ''
        while true; do
          if ! ${pkgs.protonvpn-cli}/bin/protonvpn-cli status | grep -q "Connected"; then
            echo "VPN-Verbindung verloren! Reconnecting..."
            ${pkgs.protonvpn-cli}/bin/protonvpn-cli c --cc DE -p UDP || true
          fi
          sleep 30
        done
      '';
    };
  };
}
