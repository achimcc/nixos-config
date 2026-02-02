# Suricata IDS - Intrusion Detection System
# Überwacht Netzwerkverkehr auf Angriffe und verdächtige Aktivitäten
{ config, pkgs, lib, ... }:

{
  # Suricata IDS Service
  services.suricata = {
    enable = true;

    settings = {
      # Netzwerkinterface für Paket-Capture (WiFi)
      af-packet = [
        {
          interface = "wlp0s20f3";
          cluster-id = 99;
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
      ExecStart = "${pkgs.suricata}/bin/suricata-update";
      ExecStartPost = "${pkgs.systemd}/bin/systemctl reload suricata.service";
      User = "suricata";
      Group = "suricata";
    };
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
