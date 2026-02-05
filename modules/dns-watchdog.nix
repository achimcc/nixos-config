# DNS Health Monitoring
# Ensures systemd-resolved stays healthy with DNS-over-TLS active

{ config, lib, pkgs, ... }:

{
  systemd.services.dns-watchdog = {
    description = "DNS Health Check";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dns-watchdog" ''
        set -euo pipefail

        TEST_DOMAIN="cloudflare.com"

        send_alert() {
          local msg="$1"
          echo "⚠ DNS WATCHDOG: $msg"

          ${pkgs.sudo}/bin/sudo -u achim DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
            ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=network-error \
            "DNS Failure" "$msg" 2>/dev/null || true

          echo "$msg" | ${pkgs.systemd}/bin/systemd-cat -t dns-watchdog -p err
        }

        # Check 1: systemd-resolved running
        if ! systemctl is-active --quiet systemd-resolved.service; then
          send_alert "systemd-resolved not active!"
          systemctl restart systemd-resolved.service
          exit 1
        fi

        # Check 2: DNS stub listener responding
        if ! ${pkgs.dnsutils}/bin/dig @127.0.0.53 "$TEST_DOMAIN" +timeout=3 +tries=1 &>/dev/null; then
          send_alert "DNS stub listener not responding!"
          systemctl restart systemd-resolved.service
          exit 1
        fi

        # Check 3: DNS-over-TLS active
        if ! ${pkgs.systemd}/bin/resolvectl status | grep -q "+DNSOverTLS"; then
          send_alert "DNS-over-TLS not active!"
          systemctl restart systemd-resolved.service
          exit 1
        fi

        echo "✓ DNS fully operational"
      '';
    };
  };

  systemd.timers.dns-watchdog = {
    description = "DNS Health Check Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "5min";
      Unit = "dns-watchdog.service";
    };
  };

  environment.systemPackages = with pkgs; [ dnsutils ];
}
