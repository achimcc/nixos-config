# Automated Security Monitoring
# Aggregiert Logs von AIDE, Suricata, Fail2ban, USBGuard, ClamAV, etc.
# Erstellt tägliche Security Reports und überwacht kritische Ereignisse
#
# HINWEIS: NixOS hat kein services.logwatch - wir verwenden custom systemd-Services

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # DAILY SECURITY REPORT SERVICE
  # ==========================================

  systemd.services.daily-security-report = {
    description = "Daily Security Report - Aggregiert alle Security Events";

    serviceConfig = {
      Type = "oneshot";
      User = "root";

      # Sicherheit: Private /tmp, ReadOnly /
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/log/security-reports" ];

      # Minimale Capabilities
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
      NoNewPrivileges = true;
    };

    script = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # ==========================================
      # KONFIGURATION
      # ==========================================

      REPORT_DIR="/var/log/security-reports"
      DATE=$(date +%Y-%m-%d)
      REPORT_FILE="$REPORT_DIR/$DATE.txt"
      COMPRESS_AFTER_DAYS=7
      DELETE_AFTER_DAYS=90

      # Erstelle Report-Verzeichnis
      mkdir -p "$REPORT_DIR"

      # ==========================================
      # REPORT HEADER
      # ==========================================

      {
        echo "=========================================="
        echo "DAILY SECURITY REPORT - $DATE"
        echo "=========================================="
        echo ""
        echo "Generated: $(date --rfc-3339=seconds)"
        echo "Hostname: $(hostname)"
        echo ""
      } > "$REPORT_FILE"

      # ==========================================
      # AIDE (FILE INTEGRITY)
      # ==========================================

      {
        echo "=========================================="
        echo "AIDE - File Integrity Monitoring"
        echo "=========================================="
        if [[ -f /var/lib/aide/aide.log ]]; then
          tail -n 50 /var/lib/aide/aide.log || echo "No AIDE log entries"
        else
          echo "AIDE log not found"
        fi
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # SURICATA (IDS/IPS)
      # ==========================================

      {
        echo "=========================================="
        echo "SURICATA - Intrusion Detection"
        echo "=========================================="
        if [[ -f /var/log/suricata/fast.log ]]; then
          # Nur Alerts vom gestrigen Tag
          grep "$(date -d yesterday +%m/%d/%Y)" /var/log/suricata/fast.log | tail -n 100 || echo "No Suricata alerts yesterday"
        else
          echo "Suricata log not found"
        fi
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # FAIL2BAN (BRUTE FORCE PROTECTION)
      # ==========================================

      {
        echo "=========================================="
        echo "FAIL2BAN - Brute Force Protection"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl -u fail2ban --since yesterday --no-pager | \
          grep -E "(Ban|Unban)" | tail -n 50 || echo "No Fail2ban activity yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # USBGUARD (USB DEVICE CONTROL)
      # ==========================================

      {
        echo "=========================================="
        echo "USBGUARD - USB Device Control"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl -u usbguard --since yesterday --no-pager | \
          grep -E "(Allowed|Blocked|Rejected)" | tail -n 50 || echo "No USBGuard activity yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # FIREWALL (NFTABLES)
      # ==========================================

      {
        echo "=========================================="
        echo "FIREWALL - Dropped Packets (Last 24h)"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl -k --since yesterday --no-pager | \
          grep -i "nft.*drop" | tail -n 50 || echo "No firewall drops logged yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # AUDIT (SYSTEM CALLS & FILE ACCESS)
      # ==========================================

      {
        echo "=========================================="
        echo "AUDIT - System Audit Events"
        echo "=========================================="
        if ${pkgs.systemd}/bin/systemctl is-active --quiet auditd; then
          ${pkgs.audit}/bin/ausearch -ts yesterday -i --summary || echo "No audit events yesterday"
        else
          echo "Auditd not running"
        fi
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # CLAMAV (ANTIVIRUS)
      # ==========================================

      {
        echo "=========================================="
        echo "CLAMAV - Antivirus Scans"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl -u clamav-daemon --since yesterday --no-pager | \
          grep -E "(FOUND|Infected)" | tail -n 50 || echo "No ClamAV detections yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # ROOTKIT SCANNERS
      # ==========================================

      {
        echo "=========================================="
        echo "ROOTKIT SCANNERS - Last Scan Results"
        echo "=========================================="

        # Chkrootkit
        if [[ -f /var/log/chkrootkit.log ]]; then
          echo "--- Chkrootkit ---"
          tail -n 20 /var/log/chkrootkit.log || echo "No chkrootkit log"
        fi

        # Rkhunter
        if [[ -f /var/log/rkhunter.log ]]; then
          echo "--- Rkhunter ---"
          grep -E "(Warning|Found)" /var/log/rkhunter.log | tail -n 20 || echo "No rkhunter warnings"
        fi

        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # SUDO USAGE
      # ==========================================

      {
        echo "=========================================="
        echo "SUDO - Privileged Command Execution"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl --since yesterday --no-pager | \
          grep -i "sudo" | tail -n 50 || echo "No sudo activity yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # FAILED LOGIN ATTEMPTS
      # ==========================================

      {
        echo "=========================================="
        echo "FAILED LOGINS - Authentication Failures"
        echo "=========================================="
        ${pkgs.systemd}/bin/journalctl --since yesterday --no-pager | \
          grep -E "(Failed password|authentication failure)" | tail -n 50 || echo "No failed login attempts yesterday"
        echo ""
      } >> "$REPORT_FILE"

      # ==========================================
      # REPORT FOOTER
      # ==========================================

      {
        echo "=========================================="
        echo "REPORT END"
        echo "=========================================="
        echo ""
        echo "Report saved to: $REPORT_FILE"
      } >> "$REPORT_FILE"

      # ==========================================
      # KOMPRIMIERUNG ALTER REPORTS
      # ==========================================

      # Reports älter als 7 Tage komprimieren
      find "$REPORT_DIR" -name "*.txt" -mtime +$COMPRESS_AFTER_DAYS -exec gzip {} \;

      # Reports älter als 90 Tage löschen
      find "$REPORT_DIR" -name "*.txt.gz" -mtime +$DELETE_AFTER_DAYS -delete

      echo "Daily security report generated: $REPORT_FILE"
    '';
  };

  # ==========================================
  # DAILY SECURITY REPORT TIMER
  # ==========================================

  systemd.timers.daily-security-report = {
    description = "Timer für Daily Security Report";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      # Täglich um 05:00 Uhr
      OnCalendar = "05:00";

      # Zufällige Verzögerung bis 30 Minuten (verhindert Last-Spikes)
      RandomizedDelaySec = "30min";

      # Persistent: Verpasste Runs nachholen
      Persistent = true;
    };
  };

  # ==========================================
  # CRITICAL ALERT MONITOR SERVICE
  # ==========================================

  systemd.services.critical-alert-monitor = {
    description = "Critical Security Alert Monitor - Desktop Notifications";

    serviceConfig = {
      Type = "oneshot";
      User = "root";

      # Sicherheit
      PrivateTmp = true;
      ProtectSystem = "strict";
      NoNewPrivileges = true;
    };

    script = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # ==========================================
      # FUNKTIONEN
      # ==========================================

      send_notification() {
        local title="$1"
        local message="$2"
        local urgency="critical"

        # Desktop Notification für User user
        sudo -u user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
          ${pkgs.libnotify}/bin/notify-send --urgency="$urgency" --icon=dialog-warning \
          "$title" "$message" || true

        # Zusätzlich ins System-Log
        echo "[CRITICAL ALERT] $title: $message" | ${pkgs.systemd}/bin/systemd-cat -t critical-alerts -p err
      }

      # ==========================================
      # ROOTKIT DETECTION
      # ==========================================

      # Chkrootkit
      if [[ -f /var/log/chkrootkit.log ]]; then
        if grep -qi "INFECTED\|vulnerable" /var/log/chkrootkit.log; then
          send_notification "ROOTKIT DETECTED" "Chkrootkit found suspicious activity. Check /var/log/chkrootkit.log"
        fi
      fi

      # Rkhunter
      if [[ -f /var/log/rkhunter.log ]]; then
        if grep -qi "warning\|rootkit" /var/log/rkhunter.log; then
          send_notification "ROOTKIT DETECTED" "Rkhunter found warnings. Check /var/log/rkhunter.log"
        fi
      fi

      # ==========================================
      # CRITICAL SURICATA ALERTS (Severity 1)
      # ==========================================

      if [[ -f /var/log/suricata/fast.log ]]; then
        # Suche nach Severity 1 Alerts der letzten 5 Minuten
        if grep "$(date +%m/%d/%Y)" /var/log/suricata/fast.log | grep -E "\[Priority: 1\]" | tail -n 1 | grep -q .; then
          send_notification "CRITICAL IDS ALERT" "Suricata detected high-severity threat. Check /var/log/suricata/fast.log"
        fi
      fi

      # ==========================================
      # CLAMAV VIRUS DETECTION
      # ==========================================

      # Letzte 5 Minuten nach Virus-Detections durchsuchen
      if ${pkgs.systemd}/bin/journalctl -u clamav-daemon --since "5 minutes ago" --no-pager | \
         grep -qi "FOUND\|Infected"; then
        send_notification "VIRUS DETECTED" "ClamAV found malware. Check journal: journalctl -u clamav-daemon"
      fi

      # ==========================================
      # AIDE FILE INTEGRITY VIOLATIONS
      # ==========================================

      if [[ -f /var/lib/aide/aide.log ]]; then
        # Prüfe ob Log in letzten 5 Minuten geändert wurde UND Violations enthält
        if [[ $(find /var/lib/aide/aide.log -mmin -5 2>/dev/null) ]] && \
           grep -qi "changed\|added\|removed" /var/lib/aide/aide.log; then
          send_notification "FILE INTEGRITY VIOLATION" "AIDE detected unauthorized file changes. Check /var/lib/aide/aide.log"
        fi
      fi

      # ==========================================
      # USBGUARD BLOCKS
      # ==========================================

      if ${pkgs.systemd}/bin/journalctl -u usbguard --since "5 minutes ago" --no-pager | \
         grep -qi "Blocked\|Rejected"; then
        send_notification "USB DEVICE BLOCKED" "USBGuard blocked unauthorized USB device"
      fi

      # ==========================================
      # FAILED ROOT LOGIN ATTEMPTS
      # ==========================================

      if ${pkgs.systemd}/bin/journalctl --since "5 minutes ago" --no-pager | \
         grep -E "Failed password.*root"; then
        send_notification "ROOT LOGIN ATTEMPT" "Failed root login detected. Possible attack!"
      fi
    '';
  };

  # ==========================================
  # CRITICAL ALERT MONITOR TIMER
  # ==========================================

  systemd.timers.critical-alert-monitor = {
    description = "Timer für Critical Alert Monitor";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      # Alle 5 Minuten
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";

      # Persistent: Verpasste Runs nachholen
      Persistent = true;
    };
  };

  # ==========================================
  # PAKETE
  # ==========================================

  environment.systemPackages = with pkgs; [
    logwatch
    libnotify  # Für Desktop Notifications
  ];
}
