# Email Alerts für kritische Sicherheitsereignisse
# Verwendet msmtp als leichtgewichtigen SMTP-Relay
{ config, pkgs, lib, id, ... }:

let
  # Spool für nicht zustellbare Alerts. Ohne den ging ein Alarm bei Netz-/DNS-
  # Ausfall ersatzlos verloren (nur eine msmtp-Zeile im Journal).
  undeliveredLog = "/var/log/security-alerts-undelivered.log";

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

    # Aus der Identität (privates Repo), nicht aus SOPS: Der Wert wird zur
    # BAUZEIT in dieses Script eingesetzt, sops-nix entschlüsselt aber erst zur
    # Laufzeit. Genau daran scheiterte der frühere Versuch mit
    # config.sops.placeholder an dieser Stelle.
    TO="${id.email}"
    FROM="${id.email}"
    HOSTNAME="$(${pkgs.hostname}/bin/hostname | ${pkgs.coreutils}/bin/tr -d '\r\n')"
    DATE_RFC="$(${pkgs.coreutils}/bin/date -R)"
    DATE_LONG="$(${pkgs.coreutils}/bin/date)"
    NIXOS_VER="$(/run/current-system/sw/bin/nixos-version 2>/dev/null || echo unknown)"

    # Email via printf (kein HEREDOC mit unkontrollierter Variablen-Expansion).
    # Einmal in eine Datei schreiben, damit Retries exakt dieselbe Mail senden.
    MAIL_FILE=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$MAIL_FILE"' EXIT
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
    } > "$MAIL_FILE"

    # RETRY (2026-08-15): Nach Boot/nixos-rebuild ist systemd-resolved zwar schon
    # neu gestartet, NetworkManager aber noch nicht → resolved kennt keinen
    # Upstream-Server → msmtp bricht mit NOHOST ab ("posteo.de kann nicht
    # gefunden werden"). Drei Versuche à 15 s überbrücken dieses Fenster.
    SENT=0
    for ATTEMPT in 1 2 3; do
      if ${pkgs.msmtp}/bin/msmtp --read-recipients -- "$TO" < "$MAIL_FILE"; then
        SENT=1
        break
      fi
      ${pkgs.coreutils}/bin/printf 'send-security-alert: Zustellung fehlgeschlagen (Versuch %s/3)\n' "$ATTEMPT" >&2
      if [ "$ATTEMPT" -lt 3 ]; then
        ${pkgs.coreutils}/bin/sleep 15
      fi
    done

    # Unzustellbar: Alarm NICHT verschlucken, sondern lokal spoolen. Sonst wäre
    # ein Angreifer, der nur DNS/Netz stört, automatisch auch alarmfrei.
    if [ "$SENT" -ne 1 ]; then
      ${pkgs.coreutils}/bin/printf 'send-security-alert: ALERT NICHT ZUSTELLBAR — gespoolt nach %s\n' '${undeliveredLog}' >&2
      {
        ${pkgs.coreutils}/bin/printf '=== %s | %s ===\n' "$DATE_LONG" "$SUBJECT"
        ${pkgs.coreutils}/bin/cat "$MAIL_FILE"
        ${pkgs.coreutils}/bin/printf '\n'
      } >> '${undeliveredLog}'
      exit 1
    fi
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
      # msmtp-Default ist 5 Minuten. Bei blockiertem (statt abgelehntem) Netz
      # würden 3 Retries ~15 min hängen und den Unit-Start-Timeout reißen —
      # ein Timeout failt die Unit auch mit "-"-Präfix am ExecStartPost.
      # 20 s → Worst Case 3×20 s + 2×15 s Pause = 90 s.
      timeout = 20;
    };

    accounts = {
      default = {
        host = "posteo.de";
        port = 587;
        from = id.email;
        user = id.email;
        passwordeval = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."email/posteo".path}";
      };
    };
  };

  # Log-Verzeichnis für msmtp erstellen
  systemd.tmpfiles.rules = [
    "f /var/log/msmtp.log 0600 root root -"
    # 0600: Spool enthält vollständige Alert-Mails (Dateinamen, Signaturen etc.)
    "f ${undeliveredLog} 0600 root root -"
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
  #
  # "-"-Präfix (2026-08-15): ExecStartPost zählt in das Unit-Ergebnis. Ohne das
  # Präfix machte ein gescheiterter Mailversand (msmtp exit 68) aus einem
  # erfolgreichen Check ein "failed" — und `nixos-rebuild switch` brach mit
  # exit 4 ab, obwohl nur die Benachrichtigung nicht rausging. Der Fehler bleibt
  # im Journal + im Spool sichtbar, reißt aber nicht den Rebuild mit.
  systemd.services.aide-check = {
    serviceConfig = {
      ExecStartPost = "-" + pkgs.writeShellScript "aide-alert" ''
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
      # "-"-Präfix: siehe aide-check oben — Mailfehler darf den Scan nicht failen.
      ExecStartPost = "-" + pkgs.writeShellScript "unhide-alert" ''
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

  # DEAKTIVIERT (2026-06-24): Kill Switch ist aus, VPN ist optional.
  # Keine E-Mail-Warnung mehr, wenn proton0 fehlt.
  # Reaktivierung: enable = true (oder Zeile entfernen).
  systemd.timers.vpn-failure-alert = {
    enable = false;
    description = "VPN Failure Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30min";  # Nicht sofort nach Boot
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
