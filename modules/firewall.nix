# Firewall & VPN Kill Switch Konfiguration (nftables)
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NFTABLES AKTIVIEREN
  # ==========================================

  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    checkReversePath = "loose"; # Wichtig für WireGuard/ProtonVPN
  };

  # ==========================================
  # VPN KILL SWITCH REGELN
  # ==========================================

  networking.nftables.tables.vpn-killswitch = {
    family = "inet";
    content = ''
      # VPN-Ports zentral definiert
      define vpn_ports_udp = { 51820, 1194, 443, 500, 4500 }
      define vpn_ports_tcp = { 443 }
      
      # DNS-over-TLS Server (Cloudflare & Quad9)
      define dns_servers = { 1.1.1.1, 9.9.9.9 }

      # ProtonVPN API Server (für Login & Serverliste vor VPN-Aufbau)
      define proton_api = { 185.159.158.0/24, 185.159.159.0/24 }

      chain output {
        # priority 100 = nach NixOS-Firewall (priority 0), damit wir das letzte Wort haben
        type filter hook output priority 100; policy drop;

        # Nur IPv4 in dieser Chain behandeln
        meta nfproto ipv6 jump output_ipv6

        # 1. Loopback erlauben (Lokale Prozesse)
        oifname "lo" accept

        # 2. Bestehende Verbindungen erlauben
        ct state established,related accept

        # 3. VPN Interfaces erlauben (Hier darf alles raus!)
        # proton0 = Proton App Interface, tun* = OpenVPN, wg* = WireGuard
        oifname "proton0" accept
        oifname "tun*" accept
        oifname "wg*" accept

        # 4. VPN Verbindungsaufbau erlauben (Physical Interface)
        meta nfproto ipv4 udp dport $vpn_ports_udp accept
        meta nfproto ipv4 tcp dport $vpn_ports_tcp accept

        # 5. DHCP erlauben (Sonst keine Verbindung zum WLAN)
        meta nfproto ipv4 udp dport 67-68 accept

        # 6. DNS-over-TLS für systemd-resolved (Port 853 zu DoT-Servern)
        ip daddr $dns_servers tcp dport 853 accept
        
        # 7. Lokaler DNS via systemd-resolved (127.0.0.53)
        ip daddr 127.0.0.53 udp dport 53 accept
        ip daddr 127.0.0.53 tcp dport 53 accept

        # 8. Standard DNS für VPN-Verbindungsaufbau (Hostname-Auflösung vor VPN)
        # Notwendig, da VPN-Server als Hostname (z.B. de-123.protonvpn.net) angegeben werden
        ip daddr $dns_servers udp dport 53 accept
        ip daddr $dns_servers tcp dport 53 accept

        # 9. ProtonVPN API erlauben (Login, Serverliste, Account-Verwaltung)
        ip daddr $proton_api tcp dport 443 accept

        # 10. Lokales Netzwerk erlauben (Optional, falls du Drucker/NAS brauchst)
        # ip daddr 192.168.178.0/24 accept

        # Alles andere wird durch policy drop blockiert
      }

      # IPv6 komplett blockieren (zusätzlich zur Kernel-Deaktivierung)
      chain output_ipv6 {
        oifname "lo" accept
        drop
      }

      chain input {
        type filter hook input priority 100; policy accept;
        # IPv6 blockieren außer Loopback
        meta nfproto ipv6 iifname != "lo" drop
      }

      chain forward {
        type filter hook forward priority 100; policy accept;
        # IPv6 komplett blockieren
        meta nfproto ipv6 drop
      }
    '';
  };
}
