# Email Alerts für kritische Sicherheitsereignisse
# Verwendet msmtp als leichtgewichtigen SMTP-Relay
{ config, pkgs, lib, ... }:

let
  # Helper-Script für Email-Versand
  sendSecurityAlert = pkgs.writeShellScript "send-security-alert" ''
    #!/usr/bin/env bash
    # Usage: send-security-alert "Subject" "Body"

    SUBJECT="$1"
    BODY="$2"
    TO="achim.schneider@posteo.de"  # Hardcoded, da sops placeholder in script nicht funktioniert
    FROM="achim.schneider@posteo.de"
    HOSTNAME="$(${pkgs.hostname}/bin/hostname)"

    ${pkgs.msmtp}/bin/msmtp "$TO" <<EOF
From: $FROM
To: $TO
Subject: [NixOS Security Alert] $SUBJECT
Date: $(${pkgs.coreutils}/bin/date -R)

Security Alert from $HOSTNAME

$BODY

---
Generated: $(${pkgs.coreutils}/bin/date)
System: NixOS $(${pkgs.nix}/bin/nixos-version)
EOF
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
        from = "achim.schneider@posteo.de";
        user = "achim.schneider@posteo.de";
        passwordeval = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."email/posteo/password".path}";
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
  systemd.services.aide-check = {
    serviceConfig = {
      ExecStartPost = pkgs.writeShellScript "aide-alert" ''
        if [ $EXIT_CODE -ne 0 ]; then
          ${sendSecurityAlert} \
            "AIDE Integrity Violation Detected" \
            "AIDE file integrity check FAILED.

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
      # Prüfe auf kritische Suricata-Alerts (Priority 1)
      if [ -f /var/log/suricata/eve.json ]; then
        CRITICAL=$(${pkgs.jq}/bin/jq -r 'select(.event_type=="alert" and .alert.severity==1) | .alert.signature' \
          /var/log/suricata/eve.json 2>/dev/null | tail -5)

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
      OnBootSec = "10min";
      OnUnitActiveSec = "10min";
      Persistent = true;
    };
  };

  # VPN Failure: Email wenn VPN dauerhaft down
  systemd.services.vpn-failure-alert = {
    description = "VPN Failure Alert";
    script = ''
      if ! systemctl is-active --quiet wg-quick-proton0; then
        ${sendSecurityAlert} \
          "VPN Connection Failure" \
          "ProtonVPN WireGuard connection is DOWN.

          Kill switch is active - no internet access.
          Check logs: journalctl -u wg-quick-proton0

          Action: Restart VPN or investigate connection issue."
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
