# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

let
  # VPN-Ports zentral definiert für einfache Wartung
  vpnPorts = {
    wireguard = 51820;
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
in
{
  networking.firewall = {
    enable = true;
    checkReversePath = "loose"; # Wichtig für WireGuard/ProtonVPN

    extraCommands = ''
      # ==========================================
      # IPv4 REGELN
      # ==========================================
      
      # 1. Alles löschen & Standard auf DROP setzen
      iptables -F INPUT
      iptables -F OUTPUT
      iptables -P INPUT DROP
      iptables -P OUTPUT DROP
      
      # 2. Loopback erlauben (Lokale Prozesse)
      iptables -A INPUT -i lo -j ACCEPT
      iptables -A OUTPUT -o lo -j ACCEPT
      
      # 3. Bestehende Verbindungen erlauben
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      
      # 4. VPN Interfaces erlauben (Hier darf alles raus!)
      # proton0 = Proton App Interface, tun+ = OpenVPN, wg+ = WireGuard
      iptables -A OUTPUT -o proton0 -j ACCEPT
      iptables -A OUTPUT -o tun+ -j ACCEPT
      iptables -A OUTPUT -o wg+ -j ACCEPT
      
      # 5. WICHTIG: Erlaube den Verbindungsaufbau zum VPN (Physical Interface)
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguard} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.openvpn} -j ACCEPT
      iptables -A OUTPUT -p tcp --dport ${toString vpnPorts.https} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.https} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.ikev2} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.ikev2Nat} -j ACCEPT
      
      # 6. DHCP erlauben (Sonst keine Verbindung zum WLAN)
      iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT
      
      # 7. DNS NUR über systemd-resolved (127.0.0.53) - verhindert DNS-Leaks
      iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.53 -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.53 -j ACCEPT
      
      # 8. Lokales Netzwerk erlauben (Optional, falls du Drucker/NAS brauchst)
      # iptables -A OUTPUT -d 192.168.178.0/24 -j ACCEPT

      # 9. Syncthing - Nur lokales Netzwerk (keine globalen Verbindungen)
      # Eingehende Verbindungen für lokale Discovery und Datenübertragung
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -s 192.168.0.0/16 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -s 192.168.0.0/16 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.discovery} -s 192.168.0.0/16 -j ACCEPT
      # Ausgehende Verbindungen nur ins lokale Netzwerk
      iptables -A OUTPUT -p tcp --dport ${toString syncthingPorts.tcp} -d 192.168.0.0/16 -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.quic} -d 192.168.0.0/16 -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.discovery} -d 192.168.0.0/16 -j ACCEPT

      # ==========================================
      # IPv6 REGELN - Alles blockieren (IPv6 ist deaktiviert)
      # ==========================================
      
      ip6tables -F INPUT
      ip6tables -F OUTPUT
      ip6tables -F FORWARD
      ip6tables -P INPUT DROP
      ip6tables -P OUTPUT DROP
      ip6tables -P FORWARD DROP
      
      # Nur Loopback erlauben (für lokale Prozesse)
      ip6tables -A INPUT -i lo -j ACCEPT
      ip6tables -A OUTPUT -o lo -j ACCEPT
    '';

    extraStopCommands = ''
      # IPv4 aufräumen
      iptables -P INPUT ACCEPT
      iptables -P OUTPUT ACCEPT
      iptables -F INPUT
      iptables -F OUTPUT
      
      # IPv6 aufräumen
      ip6tables -P INPUT ACCEPT
      ip6tables -P OUTPUT ACCEPT
      ip6tables -P FORWARD ACCEPT
      ip6tables -F INPUT
      ip6tables -F OUTPUT
      ip6tables -F FORWARD
    '';
  };
}
