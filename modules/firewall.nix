# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, id, vpnServer, ... }:

# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit nftables
# Migriert von iptables zu nftables am 2026-02-05
#
# SERVICE-REIHENFOLGE (KRITISCH!):
# 1. network-pre.target (Kernel-Module laden)
# 2. NetworkManager.service (Netzwerk-Interfaces aktivieren, DHCP)
# 3. network-online.target (Netzwerk ist online)
# 4. nixos-firewall.service (Firewall aktivieren - MUSS NACH network-online sein!)
# 5. vpn-boot.service (wg-1) - verbindet Slot 1 (modules/vpn.nix)

let
  # WireGuard-Endpunkte der neun Slots als nft-Konkatenation "ip . port, …".
  # Nur dorthin darf ohne Tunnel UDP raus (Handshake). Bis 2026-09-13 stand hier
  # "UDP 443/51820/88/1224/500/4500 zu JEDEM Ziel" — UDP 443 ist QUIC, Browser
  # wären damit am Kill-Switch vorbeigekommen.
  vpnEndpunkte = lib.concatMapStringsSep ", " (s: "${s.endpoint} . ${toString s.port}") vpnServer;

  # Syncthing Ports
  syncthingPorts = {
    tcp = 22000;      # Datenübertragung
    quic = 22000;     # QUIC (UDP)
    discovery = 21027; # Lokale Discovery (UDP)
  };

  # Local network configuration
  localNetwork = {
    subnet = "192.168.178.0/24";
    gateway = "192.168.178.1";
    printerIP = "192.168.178.156";
  };

  # Second local network (server network)
  secondLocalNetwork = {
    subnet = "192.168.188.0/24";
  };

  # reMarkable 2 USB network
  remarkableNetwork = {
    subnet = "10.11.99.0/24";
    deviceIP = "10.11.99.1";
  };
in
{
  # ==========================================
  # KERNEL MODULE CONFIGURATION
  # ==========================================
  # Load nftables kernel modules at boot
  # Note: counter functionality is built into nf_tables, not a separate module
  boot.kernelModules = [
    "nf_tables"
    "nf_nat"
    "nf_conntrack"
    "nft_ct"
    "nft_limit"
    "nft_nat"
    "nft_reject"
    "nft_reject_inet"
    "tun"       # Tailscale (und andere userspace VPNs) brauchen TUN-Devices
    "xt_connmark"  # Tailscale Policy-Routing
  ];

  # ==========================================
  # FIREWALL SERVICE ORDERING (KRITISCH!)
  # ==========================================
  # NixOS manages nftables.service automatically when networking.nftables.enable = true
  #
  # WICHTIG: Firewall MUSS NACH network-online.target starten!
  # Grund: systemd-resolved braucht eine funktionierende Netzwerkverbindung (IP, Route)
  # um DNS-over-TLS zu Quad9 (9.9.9.9:853) aufzubauen.
  #
  # Service-Reihenfolge beim Boot:
  # 1. systemd-resolved.service (DNS-Daemon startet)
  # 2. NetworkManager.service (Netzwerk-Interfaces, DHCP, IP-Konfiguration)
  # 3. network-online.target (Netzwerk ist ONLINE mit IP und Route)
  # 4. nftables.service (Firewall aktivieren - VPN Kill Switch)
  # 5. vpn-boot.service (Slot 1, modules/vpn.nix)
  #
  # Service-Name ist "nftables.service" (NixOS-managed)!

  # Override nftables.service: NACH network-online starten + API-IPs sofort seeden

  networking.nftables = {
    enable = true;

    ruleset = ''
      # Flush existing ruleset
      flush ruleset

      # ==========================================
      # IPv4 FIREWALL TABLE
      # ==========================================
      table inet filter {
        # Port scan detection set
        set portscan {
          type ipv4_addr
          flags dynamic, timeout
          timeout 60s
        }

        # Tailscale coordination server IPs - populated by tailscale-api-update.service
        set tailscale_api {
          type ipv4_addr
          flags timeout
        }

        # INPUT CHAIN
        chain input {
          type filter hook input priority filter; policy drop;

          # 1. Loopback traffic
          iif lo accept

          # 2. Established/Related connections
          ct state established,related accept

          # 2b. Tailscale - eingehender Traffic
          iifname "tailscale0" accept

          # 3. DHCP responses (server:67 -> client:68) - only from gateway
          ip saddr ${localNetwork.gateway} udp sport 67 udp dport 68 accept

          # 4. SECURITY: Block LLMNR/mDNS (Suricata alert mitigation)
          udp dport 5355 drop comment "Block LLMNR (credential theft risk)"
          udp dport 5353 drop comment "Block mDNS (information leakage)"

          # 5. Printer (Brother MFC-7360N) - IPP/CUPS and Raw Printing
          ip saddr ${localNetwork.printerIP} tcp sport 631 accept

          # 6. Syncthing - Local network
          ip saddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
          ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
          ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept

          # 7. Syncthing - über VPN-Interfaces
          iifname "tun*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "wg*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "tun*" udp dport ${toString syncthingPorts.quic} accept
          iifname "wg*" udp dport ${toString syncthingPorts.quic} accept

          # 7b. Workstation 192.168.178.51 - nur benötigte Dienste
          ip saddr 192.168.178.51 tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip saddr 192.168.178.51 udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept
          ip saddr 192.168.178.51 icmp type echo-request accept

          # 8. Second local network (server network) - restricted ports
          ip saddr ${secondLocalNetwork.subnet} tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip saddr ${secondLocalNetwork.subnet} udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept

          # 9. reMarkable 2 USB network - SSH and Web only
          ip saddr ${remarkableNetwork.subnet} tcp dport { 22, 80 } accept

          # 10. IPv6: ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
          meta nfproto ipv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

          # 11. IPv6 LEAK PREVENTION: Block all non-link-local IPv6 (Defense-in-Depth)
          meta nfproto ipv6 ip6 saddr != fe80::/10 drop

          # 12. Port-scan detection (3/minute Schwelle)
          # SICHERHEIT: Niedrige Schwelle erkennt auch langsame Port-Scans
          update @portscan { ip saddr limit rate over 3/minute } drop

          # 13. Dropped packets (logging temporarily disabled)
        }

        # OUTPUT CHAIN — KILL-SWITCH (seit 2026-09-13)
        # Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md
        # Ohne Tunnel geht nur raus, was ihn aufbaut (Handshake zu den neun Endpunkten,
        # DHCP), das lokale Netz und Tailscale. Ungeschützter Verkehr nur im Zustand
        # "Direkt": vpn-direkt.service füllt die Chain `direkt` (Befehl: vpn direkt).
        # Notfall ohne funktionierendes `vpn`: policy drop -> accept, nixos-rebuild.
        chain output {
          type filter hook output priority filter; policy drop;

          # 1. Loopback — auch DNS an den resolved-Stub 127.0.0.53
          oif lo accept

          # 2. Syncthing-Ratenlimit über den Tunnel (Anti-Exfiltration).
          #    Muss VOR "established" stehen, sonst trifft es nur das erste Paket.
          #    Bis 2026-09-13 stand es hinter "oifname proton0 accept" und griff nie.
          oifname "wg*" tcp dport ${toString syncthingPorts.tcp} limit rate over 10 mbytes/second drop
          oifname "wg*" udp dport ${toString syncthingPorts.quic} limit rate over 10 mbytes/second drop

          # 3. Bestehende Verbindungen — nur über Tunnel/Tailscale oder ins lokale Netz.
          #    Eine im Zustand "Direkt" geöffnete Verbindung soll nach dem Umschalten
          #    nicht am Tunnel vorbei weiterlaufen.
          ct state established,related oifname "wg*" accept
          ct state established,related oifname "tailscale0" accept
          ct state established,related ip daddr { ${localNetwork.subnet}, ${secondLocalNetwork.subnet}, ${remarkableNetwork.subnet} } accept

          # 4. Tunnel und Tailscale
          oifname "wg*" accept
          oifname "tailscale0" accept

          # 5. Tailscales eigene Pakete: tailscaled markiert seine Sockets mit 0x80000
          #    und routet sie über die Main-Tabelle am Tunnel vorbei (ip rule 5210).
          meta mark and 0xff0000 == 0x80000 accept

          # 5b. Bisherige Tailscale-Freigaben ohne Markierung, eingegrenzt auf root-Sockets
          #     (tailscaled läuft unter NixOS als root). Zuvor konnte jeder unprivilegierte
          #     Prozess (Browser) UDP 3478/41641 ohne Tunnel nutzen — STUN/TURN hätte die
          #     Heim-IP verraten bzw. Nutzdaten relayen können. Die Zähler zeigen weiterhin,
          #     ob diese Regeln neben 5 noch gebraucht werden (Messung Schritt 14).
          meta skuid 0 udp dport 41641 counter accept
          meta skuid 0 ip daddr @tailscale_api tcp dport 443 counter accept
          meta skuid 0 udp dport 3478 counter accept

          # 6. Härtung — gilt auch im Zustand "Direkt"
          udp dport 5355 drop comment "Block LLMNR (credential theft risk)"
          udp dport 5353 drop comment "Block mDNS (information leakage)"
          meta nfproto ipv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept
          meta nfproto ipv6 ip6 daddr != fe80::/10 drop

          # 7. WireGuard-Handshake — nur zu den neun Endpunkten der Serverliste
          ip daddr . udp dport { ${vpnEndpunkte} } accept

          # 8. DHCP (client:68 -> server:67)
          udp sport 68 udp dport 67 accept

          # 9. Lokales Netz (unverändert aus der Chain vor 2026-09-13)
          ip daddr ${localNetwork.gateway} tcp dport { 80, 443 } accept
          ip daddr ${localNetwork.printerIP} tcp dport 631 accept
          ip daddr ${localNetwork.printerIP} tcp dport 9100 accept
          # DoT zum Blocky des Flint-Routers (modules/network.nix). Nur 853 und nur
          # diese Adresse — steht vor "jump direkt", dessen 853-Sperre sie sonst träfe.
          ip daddr 192.168.30.1 tcp dport 853 accept
          ip daddr 192.168.178.100 tcp dport { 22, 8006 } accept
          ip daddr 192.168.178.49 tcp dport { 22, 8096, 8920 } accept
          ip daddr ${localNetwork.subnet} icmp type echo-request accept
          ip daddr 192.168.178.51 tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip daddr 192.168.178.51 udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept
          ip daddr 192.168.178.51 icmp type echo-request accept
          ip daddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept
          ip daddr 255.255.255.255 udp dport ${toString syncthingPorts.discovery} accept
          ip daddr 192.168.178.255 udp dport ${toString syncthingPorts.discovery} accept
          ip daddr ${secondLocalNetwork.subnet} tcp dport { 22, 80, 443, ${toString syncthingPorts.tcp} } accept
          ip daddr ${secondLocalNetwork.subnet} udp dport { ${toString syncthingPorts.quic}, ${toString syncthingPorts.discovery} } accept
          ip daddr ${remarkableNetwork.subnet} tcp dport { 22, 80 } accept

          # 10. Zustand "Direkt" — leer, außer vpn-direkt.service ist aktiv
          jump direkt

          # 11. Sichtbar machen, was gesperrt wird (danach greift policy drop).
          #     Kein "log" hier: modules_disabled=1 (Härtung, kein Nachladen nach dem Boot)
          #     verhindert nft_log/nf_log_syslog (gemessen 2026-09-14, lsmod leer trotz
          #     vorhandener .ko.xz) — deshalb schon der alte Kommentar "logging temporarily
          #     disabled". Zähler statt Log, ablesbar mit
          #     "sudo nft list chain inet filter output".
          counter comment "vpn-sperre"
        }

        # FORWARD CHAIN
        chain forward {
          type filter hook forward priority filter; policy drop;

          # Tailscale: Forward zwischen tailscale0 und anderen Interfaces
          iifname "tailscale0" accept
          oifname "tailscale0" accept
        }

        # Zustand "Direkt" — leer, bis vpn-direkt.service sie füllt.
        chain direkt {
        }
      }

    '';
  };

  # ==========================================
  # PER-INTERFACE REVERSE PATH FILTERING
  # ==========================================
  # Physical interfaces: strict filtering (security)
  # VPN interfaces: loose filtering (WireGuard requirement)

  boot.kernel.sysctl = {
    # WICHTIG: all.rp_filter muss gesetzt werden, aber nicht auf 0!
    # all.rp_filter = max(conf.all, conf.interface) - wir setzen auf loose (2)
    # Dann können einzelne Interfaces auf strict (1) gesetzt werden
    "net.ipv4.conf.all.rp_filter" = 2;       # loose (für VPN)
    "net.ipv4.conf.default.rp_filter" = 2;   # loose für neue interfaces

    # Per-Interface strict filtering wird dynamisch gesetzt (siehe rp-filter-setup.service)
  };

  # Dynamisches Per-Interface Reverse Path Filtering
  systemd.services.rp-filter-setup = {
    description = "Configure Per-Interface Reverse Path Filtering";
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Funktion: Setze rp_filter für Interface
      set_rp_filter() {
        local iface=$1
        local mode=$2
        local sysctl_path="/proc/sys/net/ipv4/conf/$iface/rp_filter"

        if [ -f "$sysctl_path" ]; then
          echo "$mode" > "$sysctl_path"
          echo "✓ Set rp_filter=$mode for $iface"
        fi
      }

      # Warte bis Interfaces verfügbar
      sleep 2

      # Erkenne physische Interfaces (nicht lo, nicht VPN, nicht virtuelle)
      PHYSICAL_IFACES=$(${pkgs.iproute2}/bin/ip -o link show | \
        ${pkgs.gnugrep}/bin/grep -E "^[0-9]+: (eth|enp|wlp|wlan)" | \
        ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | \
        ${pkgs.gnugrep}/bin/grep -v "@")

      # Setze strict rp_filter (1) für physische Interfaces
      for iface in $PHYSICAL_IFACES; do
        set_rp_filter "$iface" 1  # strict
      done

      # Setze loose rp_filter (2) für VPN interfaces (falls vorhanden)
      # Note: grep exits with 1 if no matches, so use || true to prevent script failure at boot
      VPN_IFACES=$(${pkgs.iproute2}/bin/ip -o link show | \
        ${pkgs.gnugrep}/bin/grep -E "^[0-9]+: (tun|wg)" | \
        ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | \
        ${pkgs.gnugrep}/bin/grep -v "@" || true)

      for iface in $VPN_IFACES; do
        set_rp_filter "$iface" 2  # loose (für WireGuard)
      done

      echo "✓ Reverse path filtering configured"
      echo "  Physical interfaces (strict): $PHYSICAL_IFACES"
      echo "  VPN interfaces (loose): $VPN_IFACES"
    '';
  };

  # nftables NACH network-online starten (siehe Kommentar oben zur Service-Reihenfolge).
  systemd.services.nftables = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = lib.mkForce [ ];
  };

  # ==========================================
  # TAILSCALE API IP UPDATE SERVICE
  # ==========================================
  # Löst Tailscale-Koordinationsserver-Domains auf und füllt das nftables Set tailscale_api.
  # Ohne diesen Service kann tailscale up die Coordination Server nicht erreichen
  # (TCP 443 auf physischen Interfaces blockiert durch Kill Switch).

  systemd.services.tailscale-api-seed = {
    description = "Seed Tailscale coordination server IPs into nftables set from persistent cache";
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "tailscale-api-seed" ''
        SEED_FILE="/var/lib/tailscale-api-seed"
        if [ -f "$SEED_FILE" ]; then
          COUNT=0
          while IFS= read -r ip; do
            [ -z "$ip" ] && continue
            ${pkgs.nftables}/bin/nft add element inet filter tailscale_api \
              "{ $ip timeout 2h }" 2>/dev/null && COUNT=$((COUNT + 1)) || true
          done < "$SEED_FILE"
          echo "✓ tailscale-api-seed: $COUNT IPs geladen"
        else
          echo "⚠ tailscale-api-seed: Keine Seed-Datei (erster Boot?)"
        fi
      '';
    };
  };

  systemd.services.tailscale-api-update = {
    description = "Update Tailscale coordination server IPs in nftables set";
    restartIfChanged = false;
    after = [ "nftables.service" "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };

    path = [ pkgs.nftables pkgs.gnugrep pkgs.curl pkgs.jq ];

    script = ''
      TIMEOUT="2h"
      RESOLVECTL="${pkgs.systemd}/bin/resolvectl"
      SEED_FILE="/var/lib/tailscale-api-seed"
      IPS_COLLECTED=""

      add_ip() {
        local ip=$1 label=$2
        ${pkgs.nftables}/bin/nft add element inet filter tailscale_api \
          "{ $ip timeout $TIMEOUT }" 2>/dev/null || true
        echo "✓ $label → $ip"
        IPS_COLLECTED="$IPS_COLLECTED
$ip"
      }

      resolve_domain() {
        local domain=$1
        local IPS
        IPS=$(timeout 5 $RESOLVECTL query -4 "$domain" 2>/dev/null \
          | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u || true)
        if [ -z "$IPS" ]; then
          echo "⚠ Keine IPs für $domain"
          return
        fi
        for ip in $IPS; do add_ip "$ip" "$domain"; done
      }

      # Phase 1: Koordinations- und Log-Domains
      echo "=== Phase 1: Koordinations-Domains ==="
      for domain in controlplane.tailscale.com login.tailscale.com log.tailscale.com; do
        resolve_domain "$domain"
      done

      # Phase 2: DERP Relay Server aus Tailscale DERP Map
      echo ""
      echo "=== Phase 2: DERP Relay Server ==="
      DERP_MAP=$(curl -s --max-time 15 \
        "https://controlplane.tailscale.com/derpmap/default" 2>/dev/null || true)
      if [ -n "$DERP_MAP" ]; then
        DERP_HOSTS=$(echo "$DERP_MAP" | jq -r '.Regions[].Nodes[].HostName' 2>/dev/null \
          | sort -u || true)
        COUNT=0
        for host in $DERP_HOSTS; do
          IPS=$(timeout 5 $RESOLVECTL query -4 "$host" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u || true)
          for ip in $IPS; do
            add_ip "$ip" "$host"
            COUNT=$((COUNT + 1))
          done
        done
        echo "✓ $COUNT DERP-IPs aufgelöst"
      else
        echo "⚠ DERP Map nicht abrufbar (kein Netz?)"
      fi

      if [ -n "$IPS_COLLECTED" ]; then
        echo "$IPS_COLLECTED" | grep -v '^$' | sort -u > "$SEED_FILE"
        echo "✓ $(wc -l < "$SEED_FILE") IPs in $SEED_FILE gespeichert"
      fi

      TOTAL=$(${pkgs.nftables}/bin/nft list set inet filter tailscale_api | grep -c "timeout" || echo "0")
      echo "=== Gesamt: $TOTAL IPs im tailscale_api Set ==="
    '';
  };

  systemd.timers.tailscale-api-update = {
    description = "Periodically update Tailscale coordination server IPs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "30min";
    };
  };
}
