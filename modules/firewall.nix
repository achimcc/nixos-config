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

      chain output {
        type filter hook output priority 0; policy drop;

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
        udp dport $vpn_ports_udp accept
        tcp dport $vpn_ports_tcp accept

        # 5. DHCP erlauben (Sonst keine Verbindung zum WLAN)
        udp dport 67-68 accept

        # 6. DNS NUR über systemd-resolved (127.0.0.53) - verhindert DNS-Leaks
        ip daddr 127.0.0.53 udp dport 53 accept
        ip daddr 127.0.0.53 tcp dport 53 accept

        # 7. Lokales Netzwerk erlauben (Optional, falls du Drucker/NAS brauchst)
        # ip daddr 192.168.178.0/24 accept

        # Alles andere wird durch policy drop blockiert
      }

      # IPv6 komplett blockieren (zusätzlich zur Kernel-Deaktivierung)
      chain output6 {
        type filter hook output priority 0; policy drop;
        oifname "lo" accept
      }

      chain input6 {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
      }

      chain forward6 {
        type filter hook forward priority 0; policy drop;
      }
    '';
  };
}
