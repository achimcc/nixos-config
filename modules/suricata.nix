# Suricata IDS - Intrusion Detection System
# Überwacht Netzwerkverkehr auf Angriffe und verdächtige Aktivitäten
{ config, pkgs, lib, ... }:

{
  # Suricata IDS Service
  services.suricata = {
    enable = true;

    settings = {
      # Threshold/Suppression Configuration
      # Unterdrückt normale lokale Netzwerk-Discovery (MDNS, LLMNR)
      threshold-file = "/etc/suricata/threshold.config";

      # Netzwerkinterfaces für Paket-Capture (WiFi + VPN GUI)
      # ACHTUNG: Nur existierende Interfaces! Fehlende Interfaces verursachen
      # Endlos-Restart-Loop → Memory-Fragmentation → kernel BUG (2026-02-17)
      af-packet = [
        {
          interface = "wlp0s20f3";  # WiFi
          cluster-id = 99;
          cluster-type = "cluster_flow";
          defrag = true;
          use-mmap = true;
          tpacket-v3 = true;
        }
        {
          interface = "proton0";  # VPN (ProtonVPN GUI WireGuard)
          cluster-id = 101;
          cluster-type = "cluster_flow";
          defrag = true;
          use-mmap = true;
          tpacket-v3 = true;
        }
      ];

      # Lokale Netzwerke definieren (VPN + Home Network)
      vars = {
        address-groups = {
          HOME_NET = "[10.2.0.0/24,192.168.178.0/24]";
          EXTERNAL_NET = "!$HOME_NET";
        };
      };

      # App-Layer Protokoll-Erkennung
      # DNP3/Modbus sind SCADA-Protokolle (irrelevant für Laptop)
      # Komplett deaktiviert → ET Open Regeln werden per disable.conf gefiltert
      app-layer.protocols = {
        modbus.enabled = "no";
        dnp3.enabled = "no";
      };

      # EVE-JSON Output für strukturierte Logs
      outputs = [
        {
          eve-log = {
            enabled = true;
            filetype = "regular";
            filename = "/var/log/suricata/eve.json";

            types = [
              { alert = {
                  payload = true;
                  payload-buffer-size = 4096;
                  payload-printable = true;
                  packet = true;
                  metadata = true;
                  http-body = true;
                  http-body-printable = true;
                };
              }
              { http = {
                  extended = true;
                };
              }
              { dns = {
                  query = true;
                  answer = true;
                };
              }
              { tls = {
                  extended = true;
                  session-resumption = true;
                };
              }
              { drop = {
                  alerts = true;
                };
              }
              { stats = {
                  totals = true;
                  threads = true;
                  deltas = false;
                };
              }
            ];
          };
        }
      ];

      # Logging-Konfiguration
      logging = {
        default-log-level = "notice";
        outputs = {
          console = {
            enabled = true;
          };
          file = {
            enabled = true;
            level = "info";
            filename = "/var/log/suricata/suricata.log";
          };
        };
      };
    };
  };

  # Restart-Limiting: Verhindert Endlos-Restart-Loops bei fehlenden Interfaces
  # Ohne diese Limits: 406 Restarts → 855MB×406 Memory-Churn → kernel BUG (2026-02-17)
  systemd.services.suricata = {
    serviceConfig.RestartSec = "30s";
    startLimitBurst = 5;
    startLimitIntervalSec = 300;
  };

  # Automatische Regel-Updates (täglich)
  systemd.services.suricata-update = {
    description = "Update Suricata Rules";

    serviceConfig = {
      Type = "oneshot";
      # Exit-Status 1 ist OK (suricata-update erfolgreich, nur reload schlägt fehl)
      SuccessExitStatus = "0 1";
    };

    script = ''
      # Enable Emerging Threats Open ruleset (free, community-maintained)
      ${pkgs.suricata}/bin/suricata-update \
        --suricata ${pkgs.suricata}/bin/suricata \
        --suricata-conf /etc/suricata/suricata.yaml \
        -o /var/lib/suricata/rules \
        list-sources | grep -q "et/open" || \
        ${pkgs.suricata}/bin/suricata-update add-source et/open

      # Update rules from configured sources
      ${pkgs.suricata}/bin/suricata-update \
        --suricata ${pkgs.suricata}/bin/suricata \
        --suricata-conf /etc/suricata/suricata.yaml \
        --disable-conf /etc/suricata/disable.conf \
        -o /var/lib/suricata/rules

      # Validate configuration before reload
      if systemctl is-active --quiet suricata.service; then
        if ${pkgs.suricata}/bin/suricata -c /etc/suricata/suricata.yaml -T; then
          echo "✓ Suricata configuration valid, rules updated successfully"
        else
          echo "ERROR: Suricata configuration validation failed after rule update" >&2
          exit 1
        fi
      fi
    '';

    # Reload Suricata nach erfolgreichem Rule-Update
    postStop = ''
      if systemctl is-active --quiet suricata.service; then
        ${pkgs.systemd}/bin/systemctl reload suricata.service 2>/dev/null || true
      fi
    '';
  };

  systemd.timers.suricata-update = {
    description = "Daily Suricata Rule Updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
  };

  # Log-Rotation für Suricata-Logs
  services.logrotate.settings.suricata = {
    files = "/var/log/suricata/*.log /var/log/suricata/*.json";
    frequency = "daily";
    rotate = 7;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    postrotate = "${pkgs.systemd}/bin/systemctl reload suricata.service";
  };

  # Pakete für Suricata und Log-Analyse
  environment.systemPackages = with pkgs; [
    suricata
    jq # Für JSON-Log-Analyse
  ];

  # Log-Verzeichnis mit korrekten Berechtigungen
  systemd.tmpfiles.rules = [
    "d /var/log/suricata 0755 suricata suricata -"
  ];

  # Disable-Konfiguration für suricata-update
  # Filtert SCADA-Regeln (DNP3, Modbus) die auf einem Laptop irrelevant sind
  # und ohne aktiviertes Protokoll "Loading signatures failed" verursachen
  # → führte zu Endlos-Restart-Loop (9094+ Restarts, 2026-02-15)
  environment.etc."suricata/disable.conf".text = ''
    # SCADA/ICS Protokolle - irrelevant für Laptop
    group:dnp3
    group:modbus
    # Fallback: Einzelne SIDs die den Start blockieren
    2270005
    2270006
    2250001
    2250002
    2250003
    2250005
    2250006
    2250007
    2250008
    2250009
  '';

  # Threshold-Konfiguration für Alert-Suppression
  environment.etc."suricata/threshold.config".text = ''
    # Suricata Threshold/Suppression Configuration
    # Unterdrückt Alerts für normale lokale Netzwerk-Discovery-Protokolle

    # Unterdrücke MDNS (Multicast DNS) Alerts aus dem lokalen Netzwerk
    # MDNS wird von macOS/Linux für lokale Service-Discovery verwendet
    suppress gen_id 1, sig_id 2027512, track by_src, ip 192.168.178.0/24
    suppress gen_id 1, sig_id 2027513, track by_src, ip 192.168.178.0/24

    # Unterdrücke LLMNR (Link-Local Multicast Name Resolution) Alerts aus dem lokalen Netzwerk
    # LLMNR wird von Windows für lokale Namensauflösung verwendet
    suppress gen_id 1, sig_id 2027857, track by_src, ip 192.168.178.0/24
    suppress gen_id 1, sig_id 2027858, track by_src, ip 192.168.178.0/24
  '';
}
