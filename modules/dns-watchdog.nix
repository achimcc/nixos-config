# DNS Health Monitoring
# Ensures systemd-resolved stays healthy with DNS-over-TLS active

{ config, lib, pkgs, ... }:

{
  systemd.services.dns-watchdog = {
    description = "DNS Health Check";

    # Ensure network and systemd-resolved are fully ready before running
    after = [ "network-online.target" "systemd-resolved.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      # Für den Zähler der aufeinanderfolgenden Fehlschläge (siehe unten).
      StateDirectory = "dns-watchdog";
      ExecStart = pkgs.writeShellScript "dns-watchdog" ''
        set -euo pipefail

        TEST_DOMAIN="cloudflare.com"
        STATE_FILE="/var/lib/dns-watchdog/consecutive-failures"

        # Erst nach so vielen Fehlschlägen IN FOLGE wird resolved neu gestartet.
        STRIKES_BEFORE_RESTART=2

        # ==========================================
        # WARUM ZWEI FEHLSCHLÄGE STATT EINEM (2026-09-12)
        # ==========================================
        # Die alte Fassung prüfte mit `dig +timeout=3 +tries=1` und startete
        # systemd-resolved bei JEDEM einzelnen Fehlschlag sofort neu. Das war
        # eine selbsterhaltende Schleife:
        #
        #   Neustart → Cache geleert UND die DNS-over-TLS-Verbindung zum
        #   Upstream abgebaut → fünf Minuten Leerlauf → die EINE Testanfrage
        #   muss erst einen TLS-Handschlag über WLAN aufbauen → dauert länger
        #   als 3 s → gilt als "stub listener not responding" → Neustart.
        #
        # Gemessen am 2026-09-12: drei Neustarts in einer Stunde (16:20, 16:45,
        # 16:50), jeder mit "Flushed all caches" für das ganze System. Nix-
        # Bauvorgänge scheiterten reproduzierbar mit "Could not resolve host:
        # cache.nixos.org", wenn sie in eines dieser Fenster fielen. Warm
        # antwortet derselbe Stub in 20–36 ms — die Grenze war also nicht zu
        # knapp bemessen, sondern der kalte Handschlag zu langsam.
        #
        # Der Wächter verursachte damit genau die Ausfälle, die er beheben soll.
        #
        # Zwei Gegenmittel:
        # 1. `+tries=3 +timeout=5` überlebt einen kalten TLS-Handschlag.
        # 2. Ein einzelner Aussetzer löst keinen systemweiten Cache-Verlust mehr
        #    aus. Ein echter Ausfall besteht auch fünf Minuten später noch und
        #    wird dann beim zweiten Mal behandelt.

        # Zählerstand lesen; alles Unerwartete gilt als 0.
        previous_failures=0
        if [ -f "$STATE_FILE" ]; then
          previous_failures=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
          # Nur Ziffern akzeptieren; leere oder beschädigte Datei zählt als 0.
          case "$previous_failures" in
            *[!0-9]*) previous_failures=0 ;;
          esac
          [ -n "$previous_failures" ] || previous_failures=0
        fi

        send_alert() {
          local msg="$1"
          echo "⚠ DNS WATCHDOG: $msg"

          # Desktop notification disabled (annoying)
          # Watchdog still logs to journalctl and auto-recovers DNS
          # ${pkgs.sudo}/bin/sudo -u <nutzer> DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
          #   ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=network-error \
          #   "DNS Failure" "$msg" 2>/dev/null || true

          echo "$msg" | ${pkgs.systemd}/bin/systemd-cat -t dns-watchdog -p err
        }

        # Ein Fehlschlag erhöht nur den Zähler. Erst beim Erreichen von
        # STRIKES_BEFORE_RESTART wird resolved angefasst.
        fail() {
          local msg="$1"
          local strikes=$((previous_failures + 1))
          echo "$strikes" > "$STATE_FILE"

          if [ "$strikes" -lt "$STRIKES_BEFORE_RESTART" ]; then
            echo "DNS-Prüfung fehlgeschlagen: $msg"
            echo "  Fehlschlag $strikes von $STRIKES_BEFORE_RESTART — noch kein Neustart."
            exit 0
          fi

          send_alert "$msg ($strikes Fehlschläge in Folge) — starte systemd-resolved neu"
          systemctl restart systemd-resolved.service
          # Zähler zurücksetzen, sonst würde ab jetzt jede Prüfung neu starten.
          echo 0 > "$STATE_FILE"
          exit 1
        }

        # Check 1: systemd-resolved running
        if ! systemctl is-active --quiet systemd-resolved.service; then
          fail "systemd-resolved not active!"
        fi

        # Check 2: DNS stub listener responding
        # +tries=3 +timeout=5: ein kalter DNS-over-TLS-Handschlag darf dauern.
        if ! ${pkgs.dnsutils}/bin/dig @127.0.0.53 "$TEST_DOMAIN" +timeout=5 +tries=3 &>/dev/null; then
          fail "DNS stub listener not responding!"
        fi

        # Check 3: DNS-over-TLS active
        status_output=$(${pkgs.systemd}/bin/resolvectl status 2>&1)
        if ! echo "$status_output" | grep -q "+DNSOverTLS"; then
          fail "DNS-over-TLS not active!"
        fi

        # Alles in Ordnung → Zähler zurücksetzen, damit vereinzelte Aussetzer
        # sich nicht über Stunden zu einem Neustart aufaddieren.
        echo 0 > "$STATE_FILE"
        echo "✓ DNS fully operational"
      '';
    };
  };

  systemd.timers.dns-watchdog = {
    description = "DNS Health Check Timer";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      # Increased from 30s to 60s to ensure systemd-resolved is fully initialized
      # DNS-over-TLS connections need time to establish
      OnBootSec = "60s";
      OnUnitActiveSec = "5min";
      Unit = "dns-watchdog.service";
    };
  };

  environment.systemPackages = with pkgs; [ dnsutils ];
}
