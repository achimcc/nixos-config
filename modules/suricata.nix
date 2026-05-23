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

      # Netzwerkinterfaces für Paket-Capture
      # tpacket-v3 + use-mmap DEAKTIVIERT auf allen Interfaces:
      # af-packet mmap Ring-Buffer löst kernel BUG at highmem.h:263
      # (kmap_local_page) auf Hardened Kernel aus. 5 Crashes waren dokumentiert
      # (02-16, 02-17, 02-20 WiFi, 02-21, 02-22 proton0). tpacket-v2 ohne mmap
      # ist minimal langsamer, aber stabil — gilt für VPN UND physische NICs.
      #
      # LAYERED DETECTION:
      # - proton0: Entschlüsselter VPN-Traffic (nutzt Malware-Regelsatz voll)
      # - wlp0s20f3 / enp0s31f6: Physischer Traffic (vor VPN-Tunnel) → erkennt
      #   lokale Angriffe (ARP-Spoofing, DHCP-Rogue, MITM-Versuche, DNS-Hijack,
      #   Scans im LAN) die am VPN vorbeilaufen würden.
      af-packet = [
        {
          interface = "proton0";  # VPN (ProtonVPN GUI WireGuard)
          cluster-id = 101;
          cluster-type = "cluster_flow";
          defrag = true;
          use-mmap = false;
          tpacket-v3 = false;
        }
        {
          interface = "wlp0s20f3";  # WLAN (physisch)
          cluster-id = 102;
          cluster-type = "cluster_flow";
          defrag = true;
          use-mmap = false;
          tpacket-v3 = false;
        }
        {
          interface = "enp0s31f6";  # Ethernet (physisch)
          cluster-id = 103;
          cluster-type = "cluster_flow";
          defrag = true;
          use-mmap = false;
          tpacket-v3 = false;
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
  # ExecReload: NixOS-Modul setzt das nicht, daher `systemctl reload` failed.
  # SIGUSR2 ist Suricatas offizielles Signal für Live-Rule-Reload ohne Capture-Gap.
  systemd.services.suricata = {
    serviceConfig.RestartSec = "30s";
    serviceConfig.ExecReload = "${pkgs.coreutils}/bin/kill -USR2 $MAINPID";
    startLimitBurst = 5;
    startLimitIntervalSec = 300;
  };

  # Automatische Regel-Updates: NixOS-Modul `services.suricata` generiert den
  # suricata-update-Service selbst (mit korrektem python3+pyyaml-Wrapper).
  # Wir überschreiben nur das Timing — Default ist OnBootSec=30s, das stört
  # bei Boot/Rebuild. RandomizedDelaySec verteilt täglich.
  systemd.timers.suricata-update = {
    timerConfig = {
      OnBootSec = lib.mkForce "15min";
      OnUnitActiveSec = lib.mkForce "24h";
      RandomizedDelaySec = "2h";
      Persistent = lib.mkForce false; # true triggert sofort bei nixos-rebuild wenn Timer überfällig
    };
  };

  # Suricata nach erfolgreichem Rule-Update neuladen (sonst bleibt der laufende
  # Prozess auf alten Regeln, neue disable-Liste wird nicht aktiv).
  # ExecReload (oben) sendet SIGUSR2 → Suricata-Live-Rule-Reload, kein Capture-Gap.
  # `+`-Prefix MUSS sein: NixOS' suricata-update.service hat DynamicUser=true,
  # der ephemerale User darf systemd-Services nicht reloaden. `+` umgeht User=
  # und führt als root aus (2026-05-19: ohne `+` blieb 3h Rule-Reload aus).
  systemd.services.suricata-update.serviceConfig.ExecStopPost = [
    "+${pkgs.writeShellScript "suricata-reload-after-update" ''
      # --no-block: return sofort, ohne auf Job-Queue-Bestätigung zu warten
      # (sonst ExecStopPost-Timeout 90s → service als 'failed' markiert, obwohl
      # Update + Reload tatsächlich erfolgreich liefen, 2026-05-22).
      if ${pkgs.systemd}/bin/systemctl is-active --quiet suricata.service; then
        ${pkgs.systemd}/bin/systemctl reload --no-block suricata.service
      fi
    ''}"
  ];

  # Log-Rotation für Suricata-Logs
  # copytruncate: Datei wird in-place geleert — Suricata muss den File-Descriptor
  # nicht neu öffnen. Ohne das ignoriert Suricata die rotierte Datei und schreibt
  # weiter in den alten (jetzt rotierten) Descriptor → Log läuft unbegrenzt voll.
  services.logrotate.settings.suricata = {
    # files MUSS eine Liste sein — als String mit Leerzeichen quotet NixOS das
    # als EINEN Pfad mit Leerzeichen, logrotate findet nichts (47GB-Bug 2026-05-16)
    files = [
      "/var/log/suricata/*.log"
      "/var/log/suricata/*.json"
    ];
    frequency = "daily";
    size = "200M";    # Auch innerhalb eines Tages rotieren wenn > 200 MB
    rotate = 5;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
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

  # Disable-Regeln: gehen über `services.suricata.disabledRules` ins NixOS-Modul.
  # Frühere `environment.etc."suricata/disable.conf"` + custom systemd-Script war
  # broken — Script rief suricata-update ohne python3+pyyaml-Wrapper auf → "pyyaml
  # is required" → set -e → die Disables wurden nie angewendet (2026-05-16).
  # ACHTUNG: suricata-update parst Inline-`# kommentar` als Teil des SID-Strings.
  # Kommentare nur auf eigene Zeilen, hier per Listen-Whitespace gruppiert.
  services.suricata.disabledRules = [
    # SCADA/ICS Protokolle - irrelevant für Laptop (Restart-Loop 2026-02-15)
    "group:dnp3"
    "group:modbus"
    # Einzelne SIDs die den Start blockierten
    "2270005" "2270006"
    "2250001" "2250002" "2250003"
    "2250005" "2250006" "2250007" "2250008" "2250009"

    # Stamus trafficid sid:3300246 "TLS1.0 connection observerd"
    # Matcht ssl_version:tls1.0 stateless auf erster ClientHello. Per RFC 8446
    # §D.4 setzen modernes TLS 1.2/1.3 die Record-Layer-Version IMMER auf 0x0301
    # für Middlebox-Kompat → feuert auf JEDE HTTPS-Verbindung. SSLV2/SSLV3
    # (3300244/3300245) bleiben aktiv — die parsen echte ServerHello-Versionen.
    "3300246"

    # Policy-violation "X in use" — Enterprise-DLP-Noise auf privatem Linux-Laptop.
    # Keine IOCs. Threat-Intel ("domain used by UNC2452/NOBELIUM" 3312621-3312642,
    # "Phishing in TLS SNI" 2048551ff, BeEF 2018090/2024415, Challack 2023140,
    # CCProxy "Hostile" 2007576) bleiben bewusst aktiv.
    "3300346"  # ChatGPT in use (openai.com SNI)
    "3300137"  # Deprecated SMBv1 protocol in use
    "3300139"  # Deprecated NTLMv1 authentication in use
    "3300145"  # LLMNR protocol in use (Windows-Namensauflösung)
    "3300147"  # NBT-NS protocol in use (Windows NetBIOS)
    "3300149"  # MDNS protocol in use
    "3300153"  # MDNS for TCP service in use
    "3300154"  # MDNS for UDP service in use
    "3300161"  # Deprecated VMWare OpenSLP service in use
    "2002112"  # ET GAMES Battle.net cdkey in use
    "2010706"  # ET INFO Internet Explorer 6 in use
    "2012247"  # ET P2P BTWebClient UA uTorrent in use

    # Stamus Chrome-Version-Tracking (3321367-3321370) — der Dataset hinkt hinter
    # Chrome-Releases nach, jede frische Auto-Update-Verbindung zu edgedl.me.gvt1.com
    # feuert "vulnerable version". 3300003-3300006 (Windows 7/8.1) sind auf Linux
    # ohnehin nie relevant.
    "3321367"  # Chrome for Win10/11 X86 vulnerable [auto update]
    "3321368"  # Chrome for Win10/11 X64 vulnerable [auto update]
    "3321369"  # Chrome for Linux vulnerable [auto update]
    "3321370"  # Chrome for macOS vulnerable [auto update]
    "3321364"  # Firefox for Windows vulnerable [auto update]
    "3321365"  # Firefox for Linux vulnerable [auto update] — incl. Mullvad ESR
    "3321366"  # Firefox for macOS vulnerable [auto update]

    # Stamus "HTTP Connection from <OS>" (3300032/3300038/3300050/3321267) —
    # feuert auf JEDE Plaintext-HTTP-Verbindung mit OS-spezifischem User-Agent.
    # Legitim: Chrome Omaha-Time-Sync (clients2.google.com/time/1/current mit
    # cup2key-Signatur — HTTP by design, da CUP integrity-signed), CRLs, OCSP,
    # NTP-Webfallback, apt-Repo HTTP-Mirrors. Enterprise-DLP-Noise auf Privatgerät.
    "3300032"  # HTTP Connection from Linux
    "3300038"  # HTTP Connection from Mageia Linux
    "3300050"  # HTTP Connection from Android
    "3321267"  # HTTP Connection from Linux GNOME

    # Go-HTTP-Client (3300111 User-Agent, 3300203/3300204 JA3-Fingerprints,
    # 2024897 ET INFO). Feuert massiv durch tailscaled (Tailscale-Agent in Go,
    # DERP-Connectivity-Probes zu derp1h.tailscale.com /generate_204 alle paar
    # Min). Würde auch jeden anderen Go-CLI/Service erfassen (kubectl, gh, ...).
    # Kein Malware-IOC: Go-HTTP ist Standard für 1000+ legitime Tools.
    "3300111"  # Go HTTP Client User-Agent
    "3300203"  # Go HTTP Client JA3 hash (b102b73a...)
    "3300204"  # Go HTTP Client JA3 hash (df669e7e...)
    "2024897"  # ET USER_AGENTS Go HTTP Client UA
  ];

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
