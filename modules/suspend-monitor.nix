# Suspend/Resume Monitoring Service
# Sammelt Fehler-Logs nach jedem Resume und zeigt Desktop-Benachrichtigung

{ config, lib, pkgs, ... }:

{
  # Post-Resume Monitoring Script
  systemd.services.suspend-resume-monitor = {
    description = "Suspend/Resume Health Monitor";

    # Wird nach jedem Resume ausgeführt
    wantedBy = [ "post-resume.target" ];
    after = [ "post-resume.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "suspend-resume-monitor" ''
        #!/usr/bin/env bash

        # Log-Datei für Suspend/Resume-Historie
        LOGFILE="/var/log/suspend-resume-monitor.log"
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        echo "=== Resume detected at $TIMESTAMP ===" >> "$LOGFILE"

        # Sammle Fehler seit letztem Boot
        ERRORS=$(${pkgs.systemd}/bin/journalctl -b -p err --since "5 minutes ago" --no-pager 2>/dev/null)

        # Prüfe auf Suspend/Resume-spezifische Fehler
        SUSPEND_ERRORS=$(echo "$ERRORS" | grep -iE "(suspend|resume|pm:|dpm_|spd5118|acpi.*power|sleep)" || echo "")

        # Suspend-Statistiken
        SUSPEND_STATS=$(cat /sys/power/suspend_stats/fail 2>/dev/null || echo "0")
        LAST_FAILED_DEV=$(cat /sys/power/suspend_stats/last_failed_dev 2>/dev/null || echo "none")

        # Log schreiben
        echo "Suspend failures: $SUSPEND_STATS" >> "$LOGFILE"
        echo "Last failed device: $LAST_FAILED_DEV" >> "$LOGFILE"

        if [ -n "$SUSPEND_ERRORS" ]; then
          echo "ERRORS DETECTED:" >> "$LOGFILE"
          echo "$SUSPEND_ERRORS" >> "$LOGFILE"

          # Desktop-Benachrichtigung für User
          # Finde aktive User-Session
          for user in $(${pkgs.systemd}/bin/loginctl list-users --no-legend | awk '{print $2}'); do
            user_id=$(id -u "$user" 2>/dev/null || continue)
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus"

            # Benachrichtigung senden
            ${pkgs.su}/bin/su - "$user" -c "${pkgs.libnotify}/bin/notify-send \
              --urgency=critical \
              --icon=dialog-warning \
              'Suspend/Resume Fehler erkannt' \
              'System hat Probleme beim Aufwachen aus Suspend. Details: journalctl -b -p err'"
          done
        else
          echo "✓ Resume successful, no errors" >> "$LOGFILE"
        fi

        echo "" >> "$LOGFILE"
      '';
    };
  };

  # Log-Rotation für Monitoring-Datei
  services.logrotate.settings.suspend-resume-monitor = {
    files = "/var/log/suspend-resume-monitor.log";
    frequency = "weekly";
    rotate = 4;
    compress = true;
  };

  # Zusätzliches Tool: Suspend-Test-Befehl für User
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "suspend-test" ''
      #!/usr/bin/env bash
      echo "=== Suspend/Resume Test-Modus ==="
      echo ""
      echo "Aktuelle Suspend-Statistiken:"
      echo "------------------------------"
      echo "Fehlgeschlagene Suspends: $(cat /sys/power/suspend_stats/fail 2>/dev/null || echo '?')"
      echo "Erfolgreich: $(cat /sys/power/suspend_stats/success 2>/dev/null || echo '?')"
      echo "Letztes fehlerhaftes Gerät: $(cat /sys/power/suspend_stats/last_failed_dev 2>/dev/null || echo 'none')"
      echo ""
      echo "Letzte Fehler seit Boot:"
      echo "------------------------------"
      journalctl -b -p err --no-pager | grep -iE "(suspend|resume|pm:|dpm_)" | tail -10
      echo ""
      echo "Monitoring-Log (letzte 20 Zeilen):"
      echo "------------------------------"
      tail -20 /var/log/suspend-resume-monitor.log 2>/dev/null || echo "Noch keine Einträge"
      echo ""
      echo "Starte kurzen Suspend-Test (5 Sekunden)..."
      echo "Drücke CTRL+C zum Abbrechen."
      sleep 2

      # 5 Sekunden Suspend
      systemctl suspend

      # Nach Resume
      sleep 2
      echo ""
      echo "✓ Resume erfolgreich!"
      echo "Prüfe auf neue Fehler..."
      journalctl -b -p err --since "1 minute ago" --no-pager | grep -iE "(suspend|resume)" || echo "✓ Keine neuen Fehler"
    '')
  ];
}
