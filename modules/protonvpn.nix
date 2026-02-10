# ProtonVPN via WireGuard mit automatischem Verbindungsaufbau beim Boot
# Sichere Credential-Speicherung via sops (Private Key, Endpoint, PublicKey)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WIREGUARD KERNEL MODUL
  # ==========================================

  # WireGuard-Kernel-Modul beim Boot laden (benötigt für wg-quick)
  # dummy-Modul für ProtonVPN GUI Kill Switch (benötigt für pvpnksintrf0 Interface)
  boot.kernelModules = [ "wireguard" "dummy" ];

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
  # HYBRID MODE: CLI autoconnect beim Boot (proton-cli) + GUI für manuellen Serverwechsel (proton0)
  systemd.services."wg-quick-proton-cli" = {
    description = "WireGuard VPN - ProtonVPN CLI (Autoconnect)";

    # Starte nach Netzwerk, sops UND Firewall (Kill Switch muss zuerst aktiv sein!)
    after = [ "network-online.target" "sops-nix.service" "nftables.service" ];
    wants = [ "network-online.target" "nftables.service" ]; # Softer dependency - won't stop VPN if firewall restarts
    # NOTE: Pre-check script still validates firewall is active before starting VPN
    # GUI MODE: Nur ProtonVPN GUI (CLI-Autoconnect deaktiviert)
    # wantedBy = [ "multi-user.target" ];  # DEAKTIVIERT - Nur GUI verwenden

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
          if systemctl is-active --quiet nftables.service; then
            # Verify firewall rules are loaded (DROP policy active)
            if ${pkgs.nftables}/bin/nft list table inet filter 2>/dev/null | grep -q "policy drop"; then
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
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${config.sops.templates."wireguard-proton-cli.conf".path}";

      # Policy Routing: Route ALL user traffic through VPN
      # WireGuard packets (to endpoint) are marked with fwmark 51820 and use main table
      # All other traffic uses table 51820 (VPN)
      ExecStartPost = pkgs.writeShellScript "vpn-policy-routing-cli" ''
        # Wait for interface to be fully up
        sleep 1

        # Priority 100: WireGuard's own packets (fwmark 51820) use main table to reach endpoint
        ${pkgs.iproute2}/bin/ip rule add fwmark 51820 table main priority 100 2>/dev/null || true

        # Priority 200: All other traffic goes through VPN (table 51820)
        # NOTE: Lower priority than GUI (101-102) so GUI takes precedence when both active
        ${pkgs.iproute2}/bin/ip rule add not fwmark 51820 table 51820 priority 200 2>/dev/null || true

        # Priority 201: Suppress default route in main table for unmarked packets (prevents leak)
        ${pkgs.iproute2}/bin/ip rule add table main suppress_prefixlength 0 priority 201 2>/dev/null || true

        echo "✓ CLI VPN policy routing active (proton-cli)"
      '';

      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${config.sops.templates."wireguard-proton-cli.conf".path}";

      # Cleanup policy routing rules on stop
      ExecStopPost = pkgs.writeShellScript "vpn-policy-routing-cli-cleanup" ''
        ${pkgs.iproute2}/bin/ip rule del fwmark 51820 table main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip rule del not fwmark 51820 table 51820 priority 200 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip rule del table main suppress_prefixlength 0 priority 201 2>/dev/null || true
        echo "✓ CLI VPN policy routing removed"
      '';

      # Aggressiver Neustart bei Fehlern (VPN Kill Switch erfordert aktives VPN!)
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Post-Up Logging
    postStart = ''
      sleep 2
      echo "ProtonVPN CLI (proton-cli) verbunden!"
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
      # Don't fail system activation when VPN is down (exit 1 is expected during rebuilds)
      # The watchdog will continue checking via timer and alert when needed
      SuccessExitStatus = "0 1";
      ExecStart = pkgs.writeShellScript "vpn-watchdog" ''
        set -euo pipefail

        # HYBRID MODE: Check both CLI (proton-cli) and GUI (proton0) interfaces
        CLI_INTERFACE="proton-cli"
        GUI_INTERFACE="proton0"
        EXPECTED_IP_PREFIX="10.2.0"
        CONNECTIVITY_HOST="1.1.1.1"
        MAX_FAILURES=3
        FAILURE_FILE="/var/run/vpn-watchdog-failures"

        send_alert() {
          local msg="$1"
          local notify="''${2:-false}"  # Optional parameter: send notification (default: false)
          echo "⚠ VPN WATCHDOG: $msg"

          # Desktop notification nur bei kritischen Problemen (notify=true)
          if [[ "$notify" == "true" ]]; then
            ${pkgs.sudo}/bin/sudo -u achim DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
              ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=network-error \
              "VPN Kill Switch Active" "$msg" 2>/dev/null || true
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
          send_alert "Firewall not active! Aborting VPN checks." "true"  # ALWAYS notify - critical!
          exit 0
        fi

        # Check 2: At least one interface exists
        cli_exists=false
        gui_exists=false

        if ${pkgs.iproute2}/bin/ip link show "$CLI_INTERFACE" &>/dev/null; then
          cli_exists=true
        fi

        if ${pkgs.iproute2}/bin/ip link show "$GUI_INTERFACE" &>/dev/null; then
          gui_exists=true
        fi

        if ! $cli_exists && ! $gui_exists; then
          # Gracefully wait for VPN to connect (CLI autoconnect or GUI after login)
          echo "ℹ No VPN interface up yet (waiting for CLI or GUI to connect)"
          reset_failures
          exit 0
        fi

        # Prefer GUI over CLI when both exist
        if $gui_exists; then
          INTERFACE="$GUI_INTERFACE"
          echo "✓ Using GUI interface ($GUI_INTERFACE)"
        else
          INTERFACE="$CLI_INTERFACE"
          echo "✓ Using CLI interface ($CLI_INTERFACE)"
        fi

        # Check 3: Interface UP
        # Note: WireGuard point-to-point interfaces show "state UNKNOWN" not "state UP"
        # Check for UP flag in interface flags instead of state field
        if ! ${pkgs.iproute2}/bin/ip link show "$INTERFACE" | grep -q "<.*UP.*>"; then
          failures=$(increment_failures)
          send_alert "Interface DOWN! (Failure $failures/$MAX_FAILURES)" "false"  # Log only

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            # Don't restart automatically - ProtonVPN GUI manages the connection
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"  # NOTIFY!
            reset_failures
          fi
          exit 1
        fi

        # Check 4: IP address assigned
        if ! ${pkgs.iproute2}/bin/ip addr show "$INTERFACE" | grep -q "inet $EXPECTED_IP_PREFIX"; then
          failures=$(increment_failures)
          send_alert "No valid IP address! (Failure $failures/$MAX_FAILURES)" "false"  # Log only

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            # Don't restart automatically - ProtonVPN GUI manages the connection
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"  # NOTIFY!
            reset_failures
          fi
          exit 1
        fi

        # Check 5: VPN routing table
        # Support both CLI (table 51820) and ProtonVPN GUI (dynamic table)
        # Check if ANY VPN interface has a default route
        if ! ${pkgs.iproute2}/bin/ip route show table all | grep -qE "default.*(proton-cli|proton0)"; then
          failures=$(increment_failures)
          send_alert "VPN routing table broken! (Failure $failures/$MAX_FAILURES)" "false"  # Log only

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            # Don't restart automatically - ProtonVPN GUI manages the connection
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"  # NOTIFY!
            reset_failures
          fi
          exit 1
        fi

        # Check 6: VPN connectivity
        if ! ${pkgs.iputils}/bin/ping -c 1 -W 3 -I "$INTERFACE" "$CONNECTIVITY_HOST" &>/dev/null; then
          failures=$(increment_failures)
          send_alert "VPN connectivity failed! (Failure $failures/$MAX_FAILURES)" "false"  # Log only

          if [[ "$failures" -ge "$MAX_FAILURES" ]]; then
            # Don't restart automatically - ProtonVPN GUI manages the connection
            send_alert "VPN connection failed after $MAX_FAILURES attempts. Please check ProtonVPN GUI." "true"  # NOTIFY!
            reset_failures
          fi
          exit 1
        fi

        # All checks passed
        current_failures=$(get_failures)
        if [[ "$current_failures" -gt 0 ]]; then
          echo "✓ VPN recovered (was failing, now healthy)"
          send_alert "VPN connection restored" "false"  # Log only, keine Notification
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
