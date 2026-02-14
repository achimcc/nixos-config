# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit nftables
# Migriert von iptables zu nftables am 2026-02-05
#
# SERVICE-REIHENFOLGE (KRITISCH!):
# 1. network-pre.target (Kernel-Module laden)
# 2. NetworkManager.service (Netzwerk-Interfaces aktivieren, DHCP)
# 3. network-online.target (Netzwerk ist online)
# 4. nixos-firewall.service (Firewall aktivieren - MUSS NACH network-online sein!)
# 5. ProtonVPN GUI (proton0) - verbindet nach Login

let
  # VPN configuration
  vpnRoutingTable = 51820;  # WireGuard routing table

  # VPN-Ports zentral definiert für einfache Wartung
  vpnPorts = {
    wireguard = 51820;
    wireguardAlt1 = 88;      # ProtonVPN WireGuard alternativ
    wireguardAlt2 = 1224;    # ProtonVPN WireGuard alternativ
    openvpn = 1194;
    https = 443;
    ikev2 = 500;
    ikev2Nat = 4500;
  };

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
    printerIP = "192.168.178.28";
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

  # DNS configuration
  dnsServers = {
    mullvad = "194.242.2.2";  # DNS-over-TLS
    stubListener = "127.0.0.53";
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
    "nft_ct"
    "nft_limit"
    "nft_nat"
    "nft_reject"
    "nft_reject_inet"
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
  # 5. wg-quick-proton-cli.service (VPN CLI autoconnect)
  # 6. ProtonVPN GUI (optional, creates proton0 interface after login)
  #
  # Service-Name ist "nftables.service" (NixOS-managed)!

  # Override nftables.service to start AFTER network-online.target
  systemd.services.nftables = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # KRITISCH: mkForce überschreibt NixOS-Default (before=network-pre.target)
    # um systemd ordering cycle zu vermeiden. Ohne mkForce: ordering cycle
    # → systemd entfernt NetworkManager aus Boot → kein Netzwerk!
    # KRITISCH: mkForce überschreibt NixOS-Default (before=network-pre.target)
    # um systemd ordering cycle zu vermeiden. Leere Liste = kein before-Constraint.
    before = lib.mkForce [ ];
  };

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

        # INPUT CHAIN
        chain input {
          type filter hook input priority filter; policy drop;

          # 1. Loopback traffic
          iif lo accept

          # 2. Established/Related connections
          ct state established,related accept

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

          # 7. Syncthing - Over VPN interfaces (HYBRID MODE: CLI + GUI)
          iifname "proton-cli" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "proton0" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "tun*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "wg*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "proton-cli" udp dport ${toString syncthingPorts.quic} accept
          iifname "proton0" udp dport ${toString syncthingPorts.quic} accept
          iifname "tun*" udp dport ${toString syncthingPorts.quic} accept
          iifname "wg*" udp dport ${toString syncthingPorts.quic} accept

          # 8. Second local network (server network) - allow all traffic
          ip saddr ${secondLocalNetwork.subnet} accept

          # 9. reMarkable 2 USB network
          ip saddr ${remarkableNetwork.subnet} accept

          # 10. IPv6: ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
          meta nfproto ipv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

          # 11. IPv6 LEAK PREVENTION: Block all non-link-local IPv6 (Defense-in-Depth)
          meta nfproto ipv6 ip6 saddr != fe80::/10 drop

          # 12. Port-scan detection (3/minute Schwelle)
          # SICHERHEIT: Niedrige Schwelle erkennt auch langsame Port-Scans
          update @portscan { ip saddr limit rate over 3/minute } drop

          # 13. Dropped packets (logging temporarily disabled)
        }

        # OUTPUT CHAIN
        chain output {
          type filter hook output priority filter; policy drop;

          # 1. Loopback traffic
          oif lo accept

          # 2. Established/Related connections
          ct state established,related accept

          # 3. VPN interfaces - allow ALL traffic (HYBRID MODE: CLI + GUI)
          oifname "proton-cli" accept
          oifname "proton0" accept
          oifname "tun*" accept
          oifname "wg*" accept

          # 4. VPN connection establishment (NUR physische Interfaces, NUR UDP)
          # SICHERHEIT: Explizit auf Nicht-VPN-Interfaces beschränkt (Defense-in-Depth)
          # VPN-Interfaces werden bereits durch Regel 3 oben abgedeckt (blanket accept)
          # WireGuard-Handshake ist verschlüsselt - kein Daten-Leak möglich
          # ProtonVPN WireGuard nutzt: UDP 443, 88, 1224, 51820, 500, 4500
          # WICHTIG: UDP 443 wird benötigt! ProtonVPN GUI versucht Port 443 zuerst.
          # Ohne UDP 443: WireGuard-Handshake timeout → GUI crasht → kein Netzwerk
          # NUR UDP erlaubt (kein TCP 443 = kein HTTPS-Leak ohne VPN)
          oifname != { "proton-cli", "proton0" } udp dport { ${toString vpnPorts.https}, ${toString vpnPorts.wireguard}, ${toString vpnPorts.wireguardAlt1}, ${toString vpnPorts.wireguardAlt2}, ${toString vpnPorts.ikev2}, ${toString vpnPorts.ikev2Nat} } accept

          # 5. DHCP requests (client:68 -> broadcast:67)
          udp sport 68 udp dport 67 accept

          # 6. DNS to systemd-resolved stub only
          ip daddr ${dnsServers.stubListener} udp dport 53 accept
          ip daddr ${dnsServers.stubListener} tcp dport 53 accept

          # 7. DNS-over-TLS - Bootstrap phase (Quad9)
          ip daddr 9.9.9.9 tcp dport 853 accept

          # 8. DNS-over-TLS - VPN phase (Mullvad) (HYBRID MODE: CLI + GUI)
          oifname "proton-cli" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
          oifname "proton0" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
          oifname "tun*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
          oifname "wg*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept

          # 9. Block all other DNS-over-TLS (prevent leaks)
          tcp dport 853 drop
          udp dport 853 drop

          # 10. SECURITY: Block LLMNR/mDNS outbound (Suricata alert mitigation)
          udp dport 5355 drop comment "Block LLMNR (credential theft risk)"
          udp dport 5353 drop comment "Block mDNS (information leakage)"

          # 11. Printer access
          ip daddr ${localNetwork.printerIP} tcp dport 631 accept
          ip daddr ${localNetwork.printerIP} tcp dport 9100 accept

          # 12. Syncthing - Local network only
          ip daddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
          ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept

          # 13. Syncthing broadcast discovery
          ip daddr 255.255.255.255 udp dport ${toString syncthingPorts.discovery} accept
          ip daddr 192.168.178.255 udp dport ${toString syncthingPorts.discovery} accept

          # 14. Egress Rate Limiting - Syncthing (Anti-Exfiltration)
          # Begrenzt Datenübertragung über VPN auf 10 MB/s pro Verbindung
          oifname { "proton-cli", "proton0" } tcp dport ${toString syncthingPorts.tcp} limit rate over 10 mbytes/second drop
          oifname { "proton-cli", "proton0" } udp dport ${toString syncthingPorts.quic} limit rate over 10 mbytes/second drop

          # 15. Second local network (server network) - allow all traffic
          ip daddr ${secondLocalNetwork.subnet} accept

          # 16. reMarkable 2 USB network (SSH, HTTP, etc.)
          ip daddr ${remarkableNetwork.subnet} accept

          # 17. IPv6: ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
          meta nfproto ipv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept

          # 18. IPv6 LEAK PREVENTION: Block all non-link-local IPv6 (Defense-in-Depth)
          # Even though IPv6 is disabled at kernel level, this prevents leaks if accidentally enabled
          meta nfproto ipv6 ip6 daddr != fe80::/10 drop

          # 19. Dropped packets (logging temporarily disabled)
        }

        # FORWARD CHAIN
        chain forward {
          type filter hook forward priority filter; policy drop;

          # Block all forwarding (logging temporarily disabled - this machine is not a router)
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
      # HYBRID MODE: Match both proton-cli (CLI) and proton0 (GUI)
      VPN_IFACES=$(${pkgs.iproute2}/bin/ip -o link show | \
        ${pkgs.gnugrep}/bin/grep -E "^[0-9]+: (tun|wg|proton-cli|proton0)" | \
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
}
