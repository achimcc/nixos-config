# Email Alerts für kritische Sicherheitsereignisse
# Verwendet msmtp als leichtgewichtigen SMTP-Relay
{ config, pkgs, lib, ... }:

let
  # Helper-Script für Email-Versand
  # SECURITY: Subject/Body werden strikt sanitiert gegen Header-Injection,
  # da Aufrufer dynamische Inhalte aus Suricata/ClamAV/AIDE einbetten (die
  # potentiell attacker-kontrollierten Content enthalten können — z.B.
  # Dateinamen, Alert-Signatures, Pfade).
  sendSecurityAlert = pkgs.writeShellScript "send-security-alert" ''
    #!/usr/bin/env bash
    set -eu
    # Usage: send-security-alert "Subject" "Body"

    # Sanitize Subject: entferne CR/LF (Header-Injection), limitiere auf 200 Zeichen
    SUBJECT=$(${pkgs.coreutils}/bin/printf '%s' "$1" \
      | ${pkgs.coreutils}/bin/tr -d '\r\n' \
      | ${pkgs.coreutils}/bin/head -c 200)

    # Sanitize Body: entferne NUR \r (CRLF-Injection), \n im Body ist OK
    BODY=$(${pkgs.coreutils}/bin/printf '%s' "$2" \
      | ${pkgs.coreutils}/bin/tr -d '\r')

    TO="user@posteo.de"  # Hardcoded, da sops placeholder in script nicht funktioniert
    FROM="user@posteo.de"
    HOSTNAME="$(${pkgs.hostname}/bin/hostname | ${pkgs.coreutils}/bin/tr -d '\r\n')"
    DATE_RFC="$(${pkgs.coreutils}/bin/date -R)"
    DATE_LONG="$(${pkgs.coreutils}/bin/date)"
    NIXOS_VER="$(/run/current-system/sw/bin/nixos-version 2>/dev/null || echo unknown)"

    # Email via printf (kein HEREDOC mit unkontrollierter Variablen-Expansion)
    {
      ${pkgs.coreutils}/bin/printf 'From: %s\n' "$FROM"
      ${pkgs.coreutils}/bin/printf 'To: %s\n' "$TO"
      ${pkgs.coreutils}/bin/printf 'Subject: [NixOS Security Alert] %s\n' "$SUBJECT"
      ${pkgs.coreutils}/bin/printf 'Date: %s\n' "$DATE_RFC"
      ${pkgs.coreutils}/bin/printf 'Content-Type: text/plain; charset=UTF-8\n'
      ${pkgs.coreutils}/bin/printf '\n'
      ${pkgs.coreutils}/bin/printf 'Security Alert from %s\n\n' "$HOSTNAME"
      ${pkgs.coreutils}/bin/printf '%s\n\n' "$BODY"
      ${pkgs.coreutils}/bin/printf -- '---\n'
      ${pkgs.coreutils}/bin/printf 'Generated: %s\n' "$DATE_LONG"
      ${pkgs.coreutils}/bin/printf 'System: NixOS %s\n' "$NIXOS_VER"
    } | ${pkgs.msmtp}/bin/msmtp --read-recipients -- "$TO"
  '';

in {
  # msmtp für Email-Versand konfigurieren
  programs.msmtp = {
    enable = true;
    setSendmail = true;  # Als Standard-Sendmail verwenden
    defaults = {
      auth = true;
      tls = true;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      logfile = "/var/log/msmtp.log";
    };

    accounts = {
      default = {
        host = "posteo.de";
        port = 587;
        from = "user@posteo.de";
        user = "user@posteo.de";
        passwordeval = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."email/posteo".path}";
      };
    };
  };

  # Log-Verzeichnis für msmtp erstellen
  systemd.tmpfiles.rules = [
    "f /var/log/msmtp.log 0600 root root -"
  ];

  # Helper-Script in systemPackages verfügbar machen
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "send-security-alert" ''
      #!/usr/bin/env bash
      exec ${sendSecurityAlert} "$@"
    '')
  ];

  # AIDE: Email bei Integritätsverletzungen
  # Hinweis: $EXIT_CODE ist nur in ExecStopPost verfügbar, NICHT in ExecStartPost.
  # Daher prüfen wir den Journal-Output von AIDE statt den Exit-Code.
  systemd.services.aide-check = {
    serviceConfig = {
      ExecStartPost = pkgs.writeShellScript "aide-alert" ''
        if journalctl -u aide-check --since "5 minutes ago" | grep -q "AIDE found differences"; then
          ${sendSecurityAlert} \
            "AIDE Integrity Violation Detected" \
            "AIDE detected unexpected file changes between rebuilds.

            Critical system files have been modified.
            Check logs: journalctl -u aide-check

            This may indicate:
            - Unauthorized system modification
            - Rootkit installation
            - Configuration tampering

            Action required: Investigate immediately."
        fi
      '';
    };
  };

  # Rootkit Detection: Email bei Funden
  systemd.services.unhide-check = {
    serviceConfig = {
      ExecStartPost = pkgs.writeShellScript "unhide-alert" ''
        if journalctl -u unhide-check --since "1 hour ago" | grep -qi "found"; then
          ${sendSecurityAlert} \
            "Rootkit Detection: Hidden Processes Found" \
            "unhide scan detected hidden processes.

            This may indicate rootkit infection.
            Check logs: journalctl -u unhide-check

            Action required: System may be compromised."
        fi
      '';
    };
  };

  # ClamAV Virus Detection Monitor
  systemd.services.clamav-alert-monitor = {
    description = "ClamAV Virus Detection Alert";
    script = ''
      if journalctl -u clamonacc --since "5 minutes ago" | grep -qi "FOUND"; then
        INFECTED=$(journalctl -u clamonacc --since "5 minutes ago" | grep "FOUND" | tail -5)
        ${sendSecurityAlert} \
          "Virus Detected by ClamAV" \
          "ClamAV detected infected files:

          $INFECTED

          Files have been blocked (OnAccessPrevention=yes).
          Check logs: journalctl -u clamonacc

          Action: Remove infected files."
      fi
    '';
  };

  systemd.timers.clamav-alert-monitor = {
    description = "ClamAV Alert Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };

  # Suricata: Email bei kritischen IDS-Alerts
  systemd.services.suricata-alert-monitor = {
    description = "Suricata IDS Alert Monitor";
    script = ''
      # Prüfe auf kritische Suricata-Alerts (Priority 1), filtere bekannte False Positives
      if [ -f /var/log/suricata/eve.json ]; then
        # Zeit-Filter: nur Alerts der letzten 65 Min (Timer-Intervall 1h + 5min Puffer).
        # OHNE diesen Filter zog `tail -5` immer die letzten matchenden Events aus der
        # GANZEN eve.json — alte Hits wurden stundenlang gemailt obwohl die zugehörige
        # Regel längst disabled war (2026-05-22 Go-HTTP-Spam-Schleife).
        # String-Vergleich statt fromdateiso8601 weil jq die Microseconds + TZ-Offset
        # von Suricata ("2026-05-22T08:20:01.172231+0200") nicht parst. Beide Seiten
        # in lokaler TZ ohne TZ-Suffix → lexikographischer Vergleich = chronologisch.
        CUTOFF=$(${pkgs.coreutils}/bin/date -d '65 minutes ago' +%Y-%m-%dT%H:%M:%S)

        # Filtere bekannte False Positives auf Signatur-Ebene:
        # - Google Cast/mDNS (harmlose Chromecast-Discovery)
        # - LLMNR (harmlose Windows Name Resolution)
        # - NBT-NS (harmlose Windows NetBIOS-Broadcasts)
        # - SSL/TLS auf ungewöhnlichen Ports (oft legitim)
        CRITICAL=$(${pkgs.jq}/bin/jq -r --arg cutoff "$CUTOFF" '
          select(.event_type=="alert" and .alert.severity==1
                 and .timestamp[0:19] >= $cutoff) |
          select(.alert.signature | test("Google Cast|[Mm][Dd][Nn][Ss]|LLMNR|NBT-NS|NetBIOS|SSL/TLS.*unusual.*port"; "i") | not) |
          .alert.signature
        ' /var/log/suricata/eve.json 2>/dev/null | tail -5)

        if [ -n "$CRITICAL" ]; then
          ${sendSecurityAlert} \
            "Critical IDS Alert from Suricata" \
            "Suricata detected critical network threats:

            $CRITICAL

            Check logs: sudo tail -f /var/log/suricata/eve.json | jq .

            Action: Investigate network activity immediately."
        fi
      fi
    '';
  };

  systemd.timers.suricata-alert-monitor = {
    description = "Suricata Alert Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "1h";  # Reduziert von 10min auf 1h
      Persistent = true;
    };
  };

  # VPN Failure: Email wenn VPN dauerhaft down
  systemd.services.vpn-failure-alert = {
    description = "VPN Failure Alert";
    script = ''
      # GUI MODE: Prüfe ob proton0 Interface existiert (von ProtonVPN GUI erstellt)
      if ! ${pkgs.iproute2}/bin/ip link show proton0 &>/dev/null; then
        ${sendSecurityAlert} \
          "VPN Connection Failure" \
          "ProtonVPN GUI connection is DOWN (no proton0 interface).

          Kill switch is active - no internet access.
          Check ProtonVPN GUI or journalctl --user -u protonvpn-gui

          Action: Open ProtonVPN GUI and reconnect."
      fi
    '';
  };

  systemd.timers.vpn-failure-alert = {
    description = "VPN Failure Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30min";  # Nicht sofort nach Boot
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
