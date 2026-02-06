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
# 5. wg-quick-proton0.service (VPN verbinden)

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
  boot.kernelModules = [
    "nf_tables"
    "nft_counter"
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
  # Firewall startet VOR NetworkManager (via NixOS default: before=network-pre.target)
  # Dies ist korrekt für einen VPN Kill Switch - verhindert Netzwerk-Leaks beim Booten.
  # DHCP/DNS funktionieren trotzdem, da die Firewall-Regeln diese erlauben.
  #
  # Service-Name ist "nftables.service" (NixOS-managed)!

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

          # 4. mDNS for local discovery (Avahi)
          udp dport 5353 ip saddr 224.0.0.251 accept

          # 5. Printer (Brother MFC-7360N) - IPP/CUPS and Raw Printing
          ip saddr ${localNetwork.printerIP} tcp sport 631 accept

          # 6. Syncthing - Local network
          ip saddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
          ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
          ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept

          # 7. Syncthing - Over VPN interfaces
          iifname "proton0" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "tun*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "wg*" tcp dport ${toString syncthingPorts.tcp} accept
          iifname "proton0" udp dport ${toString syncthingPorts.quic} accept
          iifname "tun*" udp dport ${toString syncthingPorts.quic} accept
          iifname "wg*" udp dport ${toString syncthingPorts.quic} accept

          # 8. IPv6: ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
          meta nfproto ipv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

          # 9. Port-scan detection
          update @portscan { ip saddr limit rate over 10/minute } drop

          # 10. Dropped packets (logging temporarily disabled)
        }

        # OUTPUT CHAIN
        chain output {
          type filter hook output priority filter; policy drop;

          # 1. Loopback traffic
          oif lo accept

          # 2. Established/Related connections
          ct state established,related accept

          # 3. VPN interfaces - allow ALL traffic
          oifname "proton0" accept
          oifname "tun*" accept
          oifname "wg*" accept

          # 4. VPN connection establishment (physical interface)
          udp dport ${toString vpnPorts.wireguard} accept
          udp dport ${toString vpnPorts.wireguardAlt1} accept
          udp dport ${toString vpnPorts.wireguardAlt2} accept
          udp dport ${toString vpnPorts.openvpn} accept
          tcp dport ${toString vpnPorts.https} accept
          udp dport ${toString vpnPorts.https} accept
          udp dport ${toString vpnPorts.ikev2} accept
          udp dport ${toString vpnPorts.ikev2Nat} accept

          # 5. DHCP requests (client:68 -> broadcast:67)
          udp sport 68 udp dport 67 accept

          # 6. DNS to systemd-resolved stub only
          ip daddr ${dnsServers.stubListener} udp dport 53 accept
          ip daddr ${dnsServers.stubListener} tcp dport 53 accept

          # 7. DNS-over-TLS - Bootstrap phase (Quad9)
          ip daddr 9.9.9.9 tcp dport 853 accept

          # 8. DNS-over-TLS - VPN phase (Mullvad)
          oifname "proton0" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
          oifname "tun*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
          oifname "wg*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept

          # 9. Block all other DNS-over-TLS (prevent leaks)
          tcp dport 853 drop
          udp dport 853 drop

          # 10. mDNS for local discovery
          ip daddr 224.0.0.251 udp dport 5353 accept

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

          # 14. IPv6: ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
          meta nfproto ipv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept

          # 15. Dropped packets (logging temporarily disabled)
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

    # Physical interface: strict (bessere Security)
    # PROBLEM: Interface-Name könnte sich ändern, daher auskommentiert
    # "net.ipv4.conf.wlp0s20f3.rp_filter" = 1;
  };
}
