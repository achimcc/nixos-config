# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit iptables
# Migration zu nftables mit nativen Zonen in Zukunft geplant

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
      # TODO: ProtonVPN IP-Ranges können später aus sops-Secret geladen werden
      #       (siehe docs/TODO-SOPS-PROTONVPN.md für Anleitung)

      # VPN-Ports für Verbindungsaufbau
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

      # DNS-over-TLS (Port 853) NUR über VPN zu Mullvad DNS
      # WICHTIG: DNS-Anfragen gehen nur über verschlüsseltes VPN-Interface
      iptables -A OUTPUT -o proton0 -p tcp --dport 853 -d 194.242.2.2 -j ACCEPT
      iptables -A OUTPUT -o tun+ -p tcp --dport 853 -d 194.242.2.2 -j ACCEPT
      iptables -A OUTPUT -o wg+ -p tcp --dport 853 -d 194.242.2.2 -j ACCEPT

      # Alle anderen DNS-over-TLS Verbindungen blockieren (verhindert DNS-Leaks)
      iptables -A OUTPUT -p tcp --dport 853 -j DROP
      iptables -A OUTPUT -p udp --dport 853 -j DROP
      
      # 8. mDNS für lokale Discovery (Avahi)
      iptables -A OUTPUT -p udp --dport 5353 -d 224.0.0.251 -j ACCEPT
      iptables -A INPUT -p udp --sport 5353 -j ACCEPT

      # 9. Lokales Netzwerk - MAXIMALE RESTRIKTION (nur explizit benötigte Dienste)
      #
      # Router-Zugriff (Gateway) - NUR benötigte Ports
      # DHCP (UDP 67-68) für IP-Lease
      iptables -A INPUT -s 192.168.178.1 -p udp --sport 67:68 -j ACCEPT
      iptables -A OUTPUT -d 192.168.178.1 -p udp --dport 67:68 -j ACCEPT

      # Router Web-Interface (optional, auskommentiert für mehr Sicherheit)
      # iptables -A OUTPUT -d 192.168.178.1 -p tcp --dport 80 -j ACCEPT
      # iptables -A OUTPUT -d 192.168.178.1 -p tcp --dport 443 -j ACCEPT

      # Drucker (Brother MFC-7360N) - IPP/CUPS Port 631
      # WICHTIG: Aktiviere diese Regeln und passe IP an (z.B. 192.168.178.50)
      # iptables -A INPUT -s 192.168.178.50 -p tcp --sport 631 -j ACCEPT
      # iptables -A OUTPUT -d 192.168.178.50 -p tcp --dport 631 -j ACCEPT

      # ICMP (Ping) im lokalen Netz NUR für Debugging
      # Auskommentiert für mehr Sicherheit (verhindert Netzwerk-Scans)
      # iptables -A INPUT -p icmp -s 192.168.178.0/24 -j ACCEPT
      # iptables -A OUTPUT -p icmp -d 192.168.178.0/24 -j ACCEPT

      # Syncthing wird in Abschnitt 10 separat behandelt (bereits vorhanden)

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

      # 11. Port-Scan Detection (vor Logging)
      # Erkennt und blockiert Port-Scans aggressiv
      iptables -N PORT_SCAN 2>/dev/null || true
      iptables -F PORT_SCAN
      iptables -A PORT_SCAN -m recent --set --name portscan
      iptables -A PORT_SCAN -m recent --update --seconds 60 --hitcount 10 --name portscan -j DROP
      iptables -A PORT_SCAN -j RETURN

      # Port-Scan Detection auf INPUT anwenden
      iptables -A INPUT -j PORT_SCAN

      # 12. Logging für verworfene Pakete (Intrusion Detection, aggressives Rate-Limiting)
      # WICHTIG: Muss nach allen ACCEPT-Regeln stehen, damit nur tatsächlich
      # verworfene Pakete geloggt werden (direkt vor implizitem DROP)
      iptables -A INPUT -m limit --limit 1/min --limit-burst 3 -j LOG --log-prefix "FW-DROP-IN: " --log-level 4
      iptables -A OUTPUT -m limit --limit 1/min --limit-burst 3 -j LOG --log-prefix "FW-DROP-OUT: " --log-level 4

      # ==========================================
      # IPv6 REGELN - KOMPLETT BLOCKIERT (IPv6 ist deaktiviert)
      # ==========================================

      # IPv6 ist systemweit deaktiviert (network.nix: enableIPv6 = false)
      # Firewall blockiert trotzdem alles als zusätzliche Absicherung

      # 1. Alles löschen & Standard auf DROP setzen
      ip6tables -F INPUT
      ip6tables -F OUTPUT
      ip6tables -F FORWARD
      ip6tables -P INPUT DROP
      ip6tables -P OUTPUT DROP
      ip6tables -P FORWARD DROP

      # HINWEIS: IPv6 ist deaktiviert, daher werden folgende Regeln nicht aktiv
      # Sie bleiben als Defense-in-Depth Maßnahme erhalten (falls IPv6 versehentlich aktiviert wird)

      # 2. Nur Loopback erlaubt (falls IPv6 aktiv wäre)
      ip6tables -A INPUT -i lo -j ACCEPT
      ip6tables -A OUTPUT -o lo -j ACCEPT

      # 3. Alles andere blockieren (Logging für Debugging)
      ip6tables -A INPUT -m limit --limit 1/min -j LOG --log-prefix "ip6-blocked-in: " --log-level 4
      ip6tables -A OUTPUT -m limit --limit 1/min -j LOG --log-prefix "ip6-blocked-out: " --log-level 4
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
