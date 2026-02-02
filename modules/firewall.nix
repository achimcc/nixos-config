# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

let
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
      # ProtonVPN Server IP-Ranges (für Server-Wechsel ohne Unterbrechung)
      # Quelle: https://protonvpn.com/support/protonvpn-ip-addresses
      for range in 185.159.156.0/22 185.107.56.0/22 146.70.0.0/16 156.146.32.0/20 149.88.0.0/14 193.148.16.0/20 91.219.212.0/22 89.36.76.0/22 37.120.128.0/17 79.127.141.0/24; do
        iptables -A OUTPUT -d $range -j ACCEPT
      done
      
      # VPN-Ports als Fallback für nicht-ProtonVPN Server
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguard} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguardAlt1} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguardAlt2} -j ACCEPT
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
      # DNS-over-TLS (Port 853) NUR zu Mullvad DNS - verhindert Exfiltration über DoT
      iptables -A OUTPUT -p tcp --dport 853 -d 194.242.2.2 -j ACCEPT
      
      # 8. mDNS für lokale Discovery (Avahi)
      iptables -A OUTPUT -p udp --dport 5353 -d 224.0.0.251 -j ACCEPT
      iptables -A INPUT -p udp --sport 5353 -j ACCEPT

      # 9. Lokales Netzwerk komplett freigeben
      iptables -A INPUT -s 192.168.178.0/24 -j ACCEPT
      iptables -A OUTPUT -d 192.168.178.0/24 -j ACCEPT

      # 10. Syncthing - Lokales Netzwerk und über VPN
      # Eingehende Verbindungen für lokale Discovery und Datenübertragung
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -s 192.168.178.0/24 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -s 192.168.178.0/24 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.discovery} -s 192.168.178.0/24 -j ACCEPT
      # Eingehende Verbindungen über VPN (für Relay-Verbindungen)
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i proton0 -j ACCEPT
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i tun+ -j ACCEPT
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i wg+ -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i proton0 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i tun+ -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i wg+ -j ACCEPT
      # Ausgehende Verbindungen nur ins Heimnetzwerk
      iptables -A OUTPUT -p tcp --dport ${toString syncthingPorts.tcp} -d 192.168.178.0/24 -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.quic} -d 192.168.178.0/24 -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.discovery} -d 192.168.178.0/24 -j ACCEPT
      # Broadcast für lokale Discovery (Syncthing Announce)
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.discovery} -d 255.255.255.255 -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.discovery} -d 192.168.178.255 -j ACCEPT

      # 11. Logging für verworfene Pakete (Intrusion Detection, rate-limited)
      # WICHTIG: Muss nach allen ACCEPT-Regeln stehen, damit nur tatsächlich
      # verworfene Pakete geloggt werden (direkt vor implizitem DROP)
      iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped-in: " --log-level 4
      iptables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped-out: " --log-level 4

      # ==========================================
      # IPv6 REGELN - Gleiche Logik wie IPv4
      # ==========================================

      # 1. Alles löschen & Standard auf DROP setzen
      ip6tables -F INPUT
      ip6tables -F OUTPUT
      ip6tables -F FORWARD
      ip6tables -P INPUT DROP
      ip6tables -P OUTPUT DROP
      ip6tables -P FORWARD DROP

      # 2. Loopback erlauben (Lokale Prozesse)
      ip6tables -A INPUT -i lo -j ACCEPT
      ip6tables -A OUTPUT -o lo -j ACCEPT

      # 3. Bestehende Verbindungen erlauben
      ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      # 4. VPN Interfaces erlauben
      ip6tables -A OUTPUT -o proton0 -j ACCEPT
      ip6tables -A OUTPUT -o tun+ -j ACCEPT
      ip6tables -A OUTPUT -o wg+ -j ACCEPT

      # 5. VPN-Ports erlauben (für IPv6-fähige VPN-Server)
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguard} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguardAlt1} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.wireguardAlt2} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.openvpn} -j ACCEPT
      ip6tables -A OUTPUT -p tcp --dport ${toString vpnPorts.https} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.https} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.ikev2} -j ACCEPT
      ip6tables -A OUTPUT -p udp --dport ${toString vpnPorts.ikev2Nat} -j ACCEPT

      # 6. DHCPv6 erlauben
      ip6tables -A OUTPUT -p udp --dport 546:547 -j ACCEPT
      ip6tables -A INPUT -p udp --sport 547 -j ACCEPT

      # 7. ICMPv6 für Neighbor Discovery (essentiell für IPv6)
      ip6tables -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -j ACCEPT
      ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
      ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
      ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type router-solicitation -j ACCEPT
      ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
      ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT

      # 8. DNS NUR über systemd-resolved (::1)
      ip6tables -A OUTPUT -p udp --dport 53 -d ::1 -j ACCEPT
      ip6tables -A OUTPUT -p tcp --dport 53 -d ::1 -j ACCEPT
      # DNS-over-TLS: systemd-resolved verbindet über IPv4 zu Mullvad DNS,
      # daher keine IPv6 DoT-Regel nötig (IPv4-Regel in Abschnitt oben reicht)

      # 9. mDNS für lokale Discovery
      ip6tables -A OUTPUT -p udp --dport 5353 -d ff02::fb -j ACCEPT
      ip6tables -A INPUT -p udp --sport 5353 -j ACCEPT

      # 10. Link-Local Adressen erlauben (fe80::/10)
      ip6tables -A INPUT -s fe80::/10 -j ACCEPT
      ip6tables -A OUTPUT -d fe80::/10 -j ACCEPT

      # 11. Syncthing über VPN
      ip6tables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i proton0 -j ACCEPT
      ip6tables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i tun+ -j ACCEPT
      ip6tables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i wg+ -j ACCEPT
      ip6tables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i proton0 -j ACCEPT
      ip6tables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i tun+ -j ACCEPT
      ip6tables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i wg+ -j ACCEPT

      # 12. Logging für verworfene Pakete (IPv6, rate-limited)
      # WICHTIG: Muss nach allen ACCEPT-Regeln stehen
      ip6tables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "ip6tables-dropped-in: " --log-level 4
      ip6tables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "ip6tables-dropped-out: " --log-level 4
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
