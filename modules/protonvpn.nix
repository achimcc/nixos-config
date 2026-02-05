# ProtonVPN via WireGuard mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops (Private Key, Endpoint, PublicKey)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WIREGUARD KERNEL MODUL
  # ==========================================

  # WireGuard-Kernel-Modul beim Boot laden (benötigt für wg-quick)
  boot.kernelModules = [ "wireguard" ];

  # ==========================================
  # SOPS SECRETS FÜR WIREGUARD
  # ==========================================

  sops.secrets.wireguard-private-key = {
    mode = "0400";
    owner = "root";
  };

  # Endpoint und PublicKey werden in sops.nix definiert
  # und über das Template wireguard-proton0.conf bereitgestellt

  # ==========================================
  # WIREGUARD VERZEICHNIS
  # ==========================================

  # Stelle sicher, dass das WireGuard-Verzeichnis existiert
  systemd.tmpfiles.rules = [
    "d /etc/wireguard 0700 root root -"
  ];

  # ==========================================
  # SYSTEMD SERVICE FÜR WIREGUARD
  # ==========================================

  # Eigener Service, der die sops-generierte Konfigurationsdatei verwendet
  systemd.services."wg-quick-proton0" = {
    description = "WireGuard VPN - ProtonVPN";

    # Starte nach Netzwerk, sops UND Firewall (Kill Switch muss zuerst aktiv sein!)
    after = [ "network-online.target" "sops-nix.service" "firewall.service" ];
    wants = [ "network-online.target" "firewall.service" ]; # Softer dependency - won't stop VPN if firewall restarts
    # NOTE: Pre-check script still validates firewall is active before starting VPN
    wantedBy = [ "multi-user.target" ];

    # Vor dem Display Manager starten
    before = [ "display-manager.service" ];

    # Unit-level restart limits
    startLimitBurst = 5;
    startLimitIntervalSec = 300;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Validate firewall is active before starting VPN (non-blocking check)
      ExecStartPre = pkgs.writeShellScript "vpn-pre-check" ''
        # Wait for firewall to be active (max 30s)
        for i in $(seq 1 30); do
          if systemctl is-active --quiet firewall.service; then
            # Verify firewall rules are loaded (DROP policy active)
            if ${pkgs.iptables}/bin/iptables -L OUTPUT -n | grep -q "DROP"; then
              echo "✓ Firewall active with DROP policy - safe to start VPN"
              exit 0
            fi
          fi
          sleep 1
        done

        # WARNING: Proceed anyway to avoid boot lockup
        # The VPN watchdog will monitor and alert if firewall fails later
        echo "⚠ WARNING: Firewall not active after 30s - proceeding anyway"
        echo "⚠ VPN Watchdog will monitor firewall status"
        exit 0  # Do not block system boot
      '';

      # Starte WireGuard mit der sops-generierten Konfiguration
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${config.sops.templates."wireguard-proton0.conf".path}";

      # Policy Routing: Route ALL traffic through VPN
      # Must be done AFTER wg-quick up (which creates table 51820 routes)
      ExecStartPost = pkgs.writeShellScript "vpn-policy-routing" ''
        # Wait for interface to be fully up
        sleep 1

        # Add policy routing rules to direct all traffic through VPN
        # Priority 100: All traffic (except VPN endpoint) goes through table 51820
        ${pkgs.iproute2}/bin/ip rule add not fwmark 51820 table 51820 priority 100 2>/dev/null || true

        # Priority 101: Suppress default route in main table (prevents leak)
        ${pkgs.iproute2}/bin/ip rule add table main suppress_prefixlength 0 priority 101 2>/dev/null || true

        echo "✓ VPN policy routing active"
      '';

      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${config.sops.templates."wireguard-proton0.conf".path}";

      # Cleanup policy routing rules on stop
      ExecStopPost = pkgs.writeShellScript "vpn-policy-routing-cleanup" ''
        ${pkgs.iproute2}/bin/ip rule del not fwmark 51820 table 51820 priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip rule del table main suppress_prefixlength 0 priority 101 2>/dev/null || true
        echo "✓ VPN policy routing removed"
      '';

      # Aggressiver Neustart bei Fehlern (VPN Kill Switch erfordert aktives VPN!)
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Post-Up Logging
    postStart = ''
      sleep 2
      echo "ProtonVPN WireGuard verbunden!"
    '';
  };

  # ==========================================
  # VPN WATCHDOG (Comprehensive Health Check)
  # ==========================================

  # Watchdog Service: Comprehensive 6-check VPN health monitoring
  systemd.services."vpn-watchdog" = {
    description = "VPN Watchdog - Comprehensive health check";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "vpn-watchdog" ''
        set -euo pipefail

        INTERFACE="proton0"
        EXPECTED_IP_PREFIX="10.2.0"
        CONNECTIVITY_HOST="1.1.1.1"
        MAX_FAILURES=3
        FAILURE_FILE="/var/run/vpn-watchdog-failures"

        send_alert() {
          local msg="$1"
          echo "⚠ VPN WATCHDOG: $msg"

          # Desktop notification
          ${pkgs.sudo}/bin/sudo -u achim DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
            ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=network-error \
            "VPN Kill Switch Active" "$msg" 2>/dev/null || true

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
        if ! systemctl is-active --quiet firewall.service; then
          send_alert "Firewall not active! Aborting VPN checks."
          exit 0
        fi

        # Check 2: Interface exists
        if ! ${pkgs.iproute2}/bin/ip link show "$INTERFACE" &>/dev/null; then
          failures=$(increment_failures)
          send_alert "Interface missing! (Failure $failures/$MAX_FAILURES)"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            echo "→ Restarting VPN..."
            systemctl restart wg-quick-proton0.service
            reset_failures
          fi
          exit 1
        fi

        # Check 3: Interface UP
        # Note: WireGuard point-to-point interfaces show "state UNKNOWN" not "state UP"
        # Check for UP flag in interface flags instead of state field
        if ! ${pkgs.iproute2}/bin/ip link show "$INTERFACE" | grep -q "<.*UP.*>"; then
          failures=$(increment_failures)
          send_alert "Interface DOWN! (Failure $failures/$MAX_FAILURES)"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            systemctl restart wg-quick-proton0.service
            reset_failures
          fi
          exit 1
        fi

        # Check 4: IP address assigned
        if ! ${pkgs.iproute2}/bin/ip addr show "$INTERFACE" | grep -q "inet $EXPECTED_IP_PREFIX"; then
          failures=$(increment_failures)
          send_alert "No valid IP address! (Failure $failures/$MAX_FAILURES)"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            systemctl restart wg-quick-proton0.service
            reset_failures
          fi
          exit 1
        fi

        # Check 5: VPN routing table
        if ! ${pkgs.iproute2}/bin/ip route show table 51820 | grep -q "default.*$INTERFACE"; then
          failures=$(increment_failures)
          send_alert "VPN routing table broken! (Failure $failures/$MAX_FAILURES)"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            systemctl restart wg-quick-proton0.service
            reset_failures
          fi
          exit 1
        fi

        # Check 6: VPN connectivity
        if ! ${pkgs.iputils}/bin/ping -c 1 -W 3 -I "$INTERFACE" "$CONNECTIVITY_HOST" &>/dev/null; then
          failures=$(increment_failures)
          send_alert "VPN connectivity failed! (Failure $failures/$MAX_FAILURES)"

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            systemctl restart wg-quick-proton0.service
            reset_failures
          fi
          exit 1
        fi

        # All checks passed
        current_failures=$(get_failures)
        if [[ "$current_failures" -gt 0 ]]; then
          echo "✓ VPN recovered (was failing, now healthy)"
          send_alert "VPN connection restored"
        fi

        reset_failures
        echo "✓ VPN fully operational"
      '';
    };
  };

  # Timer: Check VPN health every 30 seconds
  systemd.timers."vpn-watchdog" = {
    description = "VPN Watchdog Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "15s";        # Start earlier (was 30s)
      OnUnitActiveSec = "30s";  # Check every 30s (was 60s)
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
