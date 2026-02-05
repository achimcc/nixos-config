# ProtonVPN via WireGuard mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops (Private Key, Endpoint, PublicKey)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WIREGUARD KERNEL MODUL
  # ==========================================

  # WireGuard-Kernel-Modul beim Boot laden (benötigt für wg-quick)
  boot.kernelModules = [ "wireguard" ];

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

    # Starte nach Netzwerk, sops UND Firewall (Kill Switch muss zuerst aktiv sein!)
    after = [ "network-online.target" "sops-nix.service" "firewall.service" ];
    wants = [ "network-online.target" ];
    requires = [ "firewall.service" ]; # Firewall MUSS laufen, sonst kein VPN
    wantedBy = [ "multi-user.target" ];

    # Vor dem Display Manager starten
    before = [ "display-manager.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Starte WireGuard mit der sops-generierten Konfiguration
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${config.sops.templates."wireguard-proton0.conf".path}";
      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${config.sops.templates."wireguard-proton0.conf".path}";

      # Aggressiver Neustart bei Fehlern (VPN Kill Switch erfordert aktives VPN!)
      Restart = "on-failure";
      RestartSec = "5s";
      StartLimitBurst = 10;      # Erlaube 10 Neustarts
      StartLimitIntervalSec = 300; # In 5 Minuten
    };

    # Post-Up Logging
    postStart = ''
      sleep 2
      echo "ProtonVPN WireGuard verbunden!"
    '';
  };

  # ==========================================
  # VPN WATCHDOG (Auto-Restart bei Interface-Verlust)
  # ==========================================

  # Watchdog Service: Prüft ob proton0 existiert und startet VPN neu wenn nicht
  systemd.services."vpn-watchdog" = {
    description = "VPN Watchdog - Auto-restart if proton0 interface missing";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "vpn-watchdog" ''
        # Prüfe ob Firewall aktiv ist
        if ! systemctl is-active --quiet firewall.service; then
          echo "Firewall nicht aktiv, kein Watchdog nötig"
          exit 0
        fi

        # Prüfe ob proton0 Interface existiert
        if ! ${pkgs.iproute2}/bin/ip link show proton0 &>/dev/null; then
          echo "⚠ proton0 Interface fehlt! VPN Kill Switch aktiv aber kein VPN!"

          # Prüfe ob wg-quick-proton0 Service läuft
          if ! systemctl is-active --quiet wg-quick-proton0.service; then
            echo "→ Starte wg-quick-proton0.service neu..."
            systemctl start wg-quick-proton0.service
          else
            echo "→ Service läuft, aber Interface fehlt - Neustart..."
            systemctl restart wg-quick-proton0.service
          fi
        else
          echo "✓ proton0 Interface vorhanden"
        fi
      '';
    };
  };

  # Timer: Führt Watchdog alle 60 Sekunden aus
  systemd.timers."vpn-watchdog" = {
    description = "VPN Watchdog Timer - Check VPN every 60s";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "30s";        # Erste Prüfung 30s nach Boot
      OnUnitActiveSec = "60s";  # Dann alle 60 Sekunden
      Unit = "vpn-watchdog.service";
    };
  };

  # ==========================================
  # WIREGUARD TOOLS
  # ==========================================

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
