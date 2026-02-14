# ProtonVPN via GUI mit WireGuard
# GUI MODE: ProtonVPN GUI verwaltet die VPN-Verbindung nach Login
# Firewall Kill Switch (nftables) schützt Traffic vor VPN-Verbindung

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WIREGUARD KERNEL MODUL
  # ==========================================

  # WireGuard + dummy Kernel-Module laden
  # dummy: Benötigt von ProtonVPN GUI für Kill-Switch-Interface (pvpnksintrf0)
  # Ohne dummy crasht die GUI mit TimeoutError bei nm_client.add_connection_async()
  # Kill Switch in GUI bleibt OFF (settings.json) — unser nftables Kill Switch schützt bereits
  boot.kernelModules = [ "wireguard" "dummy" ];

  # ==========================================
  # WIREGUARD VERZEICHNIS
  # ==========================================

  # Stelle sicher, dass das WireGuard-Verzeichnis existiert
  systemd.tmpfiles.rules = [
    "d /etc/wireguard 0700 root root -"
  ];

  # ==========================================
  # VPN WATCHDOG (Health Check für GUI-Verbindung)
  # ==========================================

  # Watchdog Service: Prüft proton0 Interface (von ProtonVPN GUI erstellt)
  systemd.services."vpn-watchdog" = {
    description = "VPN Watchdog - GUI health check";

    serviceConfig = {
      Type = "oneshot";
      # Don't fail system activation when VPN is down (exit 1 is expected during rebuilds)
      # The watchdog will continue checking via timer and alert when needed
      SuccessExitStatus = "0 1";
      ExecStart = pkgs.writeShellScript "vpn-watchdog" ''
        set -euo pipefail

        # GUI MODE: Nur proton0 Interface prüfen (von ProtonVPN GUI erstellt)
        INTERFACE="proton0"
        EXPECTED_IP_PREFIX="10.2.0"
        CONNECTIVITY_HOST="1.1.1.1"
        MAX_FAILURES=3
        FAILURE_FILE="/var/run/vpn-watchdog-failures"
        NOTIFIED_FILE="/var/run/vpn-watchdog-notified"

        send_alert() {
          local msg="$1"
          local notify="''${2:-false}"
          echo "⚠ VPN WATCHDOG: $msg"

          # Desktop notification nur einmal pro Problem (nicht bei jedem Watchdog-Durchlauf)
          if [[ "$notify" == "true" ]] && [[ ! -f "$NOTIFIED_FILE" ]]; then
            ${pkgs.sudo}/bin/sudo -u achim DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
              ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=network-error \
              "VPN Kill Switch Active" "$msg" 2>/dev/null || true
            touch "$NOTIFIED_FILE"
          fi

          echo "$msg" | ${pkgs.systemd}/bin/systemd-cat -t vpn-watchdog -p warning
        }

        increment_failures() {
          local count=0
          [[ -f "$FAILURE_FILE" ]] && count=$(cat "$FAILURE_FILE")
          count=$((count + 1))
          echo "$count" > "$FAILURE_FILE"
          echo "$count"
        }

        reset_failures() {
          rm -f "$FAILURE_FILE"
        }

        get_failures() {
          [[ -f "$FAILURE_FILE" ]] && cat "$FAILURE_FILE" || echo "0"
        }

        # Check 1: Firewall active
        if ! systemctl is-active --quiet nftables.service; then
          send_alert "Firewall not active! Aborting VPN checks." "false"
          exit 0
        fi

        # Check 2: Interface exists (GUI erstellt proton0 erst nach Login + Auto-Connect)
        if ! ${pkgs.iproute2}/bin/ip link show "$INTERFACE" &>/dev/null; then
          echo "ℹ No VPN interface up yet (waiting for GUI to connect after login)"
          reset_failures
          exit 0
        fi

        echo "✓ Using GUI interface ($INTERFACE)"

        # Check 3: Interface UP
        # Note: WireGuard point-to-point interfaces show "state UNKNOWN" not "state UP"
        if ! ${pkgs.iproute2}/bin/ip link show "$INTERFACE" | grep -q "<.*UP.*>"; then
          failures=$(increment_failures)
          send_alert "Interface DOWN! (Failure $failures/$MAX_FAILURES)" "false"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"
            reset_failures
          fi
          exit 1
        fi

        # Check 4: IP address assigned
        if ! ${pkgs.iproute2}/bin/ip addr show "$INTERFACE" | grep -q "inet $EXPECTED_IP_PREFIX"; then
          failures=$(increment_failures)
          send_alert "No valid IP address! (Failure $failures/$MAX_FAILURES)" "false"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"
            reset_failures
          fi
          exit 1
        fi

        # Check 5: VPN routing table
        if ! ${pkgs.iproute2}/bin/ip route show table all | grep -q "default.*proton0"; then
          failures=$(increment_failures)
          send_alert "VPN routing table broken! (Failure $failures/$MAX_FAILURES)" "false"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"
            reset_failures
          fi
          exit 1
        fi

        # Check 6: VPN connectivity
        if ! ${pkgs.iputils}/bin/ping -c 1 -W 3 -I "$INTERFACE" "$CONNECTIVITY_HOST" &>/dev/null; then
          failures=$(increment_failures)
          send_alert "VPN connectivity failed! (Failure $failures/$MAX_FAILURES)" "false"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"
            reset_failures
          fi
          exit 1
        fi

        # All checks passed
        current_failures=$(get_failures)
        if [[ "$current_failures" -gt 0 ]]; then
          echo "✓ VPN recovered (was failing, now healthy)"
          send_alert "VPN connection restored" "false"
        fi

        reset_failures
        rm -f "$NOTIFIED_FILE"
        echo "✓ VPN fully operational"
      '';
    };
  };

  # Timer: Check VPN health every 30 seconds
  systemd.timers."vpn-watchdog" = {
    description = "VPN Watchdog Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "30s";
      Unit = "vpn-watchdog.service";
    };
  };

  # ==========================================
  # WIREGUARD TOOLS
  # ==========================================

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
