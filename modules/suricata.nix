# Suricata IDS - Intrusion Detection System
# Überwacht Netzwerkverkehr auf Angriffe und verdächtige Aktivitäten
{ config, pkgs, lib, ... }:

{
  # Suricata IDS Service
  services.suricata = {
    enable = true;

    settings = {
      # Netzwerkinterfaces für Paket-Capture (WiFi + VPN)
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
          interface = "proton0";  # VPN (ProtonVPN WireGuard)
          cluster-id = 100;
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
      app-layer.protocols = {
        modbus = {
          enabled = "detection-only";
        };
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

  # Automatische Regel-Updates (täglich)
  systemd.services.suricata-update = {
    description = "Update Suricata Rules";

    serviceConfig = {
      Type = "oneshot";
      # Exit-Status 1 ist OK (suricata-update erfolgreich, nur reload schlägt fehl)
      SuccessExitStatus = "0 1";
    };

    script = ''
      ${pkgs.suricata}/bin/suricata-update
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
}
