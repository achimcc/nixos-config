# Firewall & VPN Kill Switch Konfiguration
# Blockiert ALLEN Traffic außer über VPN-Interfaces

{ config, lib, pkgs, ... }:

# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit iptables
# Migration zu nftables mit nativen Zonen in Zukunft geplant
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
  # FIREWALL SERVICE ORDERING (KRITISCH!)
  # ==========================================
  # Firewall MUSS nach NetworkManager starten, damit DHCP/DNS funktionieren
  # ABER vor dem VPN-Start, um den Kill Switch zu garantieren
  #
  # WICHTIG: Der korrekte Service-Name ist "firewall.service" (nicht "nixos-firewall")!
  # Wir verwenden lib.mkAfter/lib.mkBefore um die Service-Dependencies zu erweitern,
  # anstatt den kompletten Service zu überschreiben.

  systemd.services.firewall = {
    after = lib.mkAfter [ "NetworkManager.service" "network-online.target" ];
    wants = lib.mkAfter [ "network-online.target" ];
    before = lib.mkBefore [ "wg-quick-proton0.service" ];

    # Unit-level restart limits
    startLimitBurst = 3;
    startLimitIntervalSec = 120;

    serviceConfig = {
      # Validate network interface is ready before starting firewall
      ExecStartPre = pkgs.writeShellScript "firewall-pre-check" ''
        # Wait for network interface with IP (max 30s)
        for i in $(seq 1 30); do
          if ${pkgs.iproute2}/bin/ip addr show | grep -q "inet.*192.168"; then
            echo "✓ Network interface ready"
            exit 0
          fi
          sleep 1
        done
        echo "⚠ Network interface not ready after 30s, proceeding anyway"
        exit 0
      '';

      # Restart policy for firewall
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  networking.firewall = {
    enable = true;
    checkReversePath = false; # We'll set per-interface via sysctl

    extraCommands = ''
      # ==========================================
      # IPv4 REGELN
      # ==========================================
      
      # 1. Alles löschen & Standard auf DROP setzen
      iptables -F INPUT
      iptables -F OUTPUT
      iptables -F FORWARD
      iptables -P INPUT DROP
      iptables -P OUTPUT DROP
      iptables -P FORWARD DROP
      
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
      
      # 7. DNS NUR über systemd-resolved (${dnsServers.stubListener}) - verhindert DNS-Leaks
      iptables -A OUTPUT -p udp --dport 53 -d ${dnsServers.stubListener} -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 53 -d ${dnsServers.stubListener} -j ACCEPT

      # DNS-over-TLS (Port 853) NUR über VPN zu Mullvad DNS
      # WICHTIG: DNS-Anfragen gehen nur über verschlüsseltes VPN-Interface
      iptables -A OUTPUT -o proton0 -p tcp --dport 853 -d ${dnsServers.mullvad} -j ACCEPT
      iptables -A OUTPUT -o tun+ -p tcp --dport 853 -d ${dnsServers.mullvad} -j ACCEPT
      iptables -A OUTPUT -o wg+ -p tcp --dport 853 -d ${dnsServers.mullvad} -j ACCEPT

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
      iptables -A INPUT -s ${localNetwork.gateway} -p udp --sport 67:68 -j ACCEPT
      iptables -A OUTPUT -d ${localNetwork.gateway} -p udp --dport 67:68 -j ACCEPT

      # Router Web-Interface (optional, auskommentiert für mehr Sicherheit)
      # iptables -A OUTPUT -d ${localNetwork.gateway} -p tcp --dport 80 -j ACCEPT
      # iptables -A OUTPUT -d ${localNetwork.gateway} -p tcp --dport 443 -j ACCEPT

      # Drucker (Brother MFC-7360N) - IPP/CUPS Port 631
      # IP-Adresse: ${localNetwork.printerIP} (via Avahi erkannt)
      iptables -A INPUT -s ${localNetwork.printerIP} -p tcp --sport 631 -j ACCEPT
      iptables -A OUTPUT -d ${localNetwork.printerIP} -p tcp --dport 631 -j ACCEPT

      # Brother-Drucker verwendet auch Raw-Printing (Port 9100)
      iptables -A OUTPUT -d ${localNetwork.printerIP} -p tcp --dport 9100 -j ACCEPT

      # ICMP (Ping) im lokalen Netz NUR für Debugging
      # Auskommentiert für mehr Sicherheit (verhindert Netzwerk-Scans)
      # iptables -A INPUT -p icmp -s ${localNetwork.subnet} -j ACCEPT
      # iptables -A OUTPUT -p icmp -d ${localNetwork.subnet} -j ACCEPT

      # Syncthing wird in Abschnitt 10 separat behandelt (bereits vorhanden)

      # 10. Syncthing - Lokales Netzwerk und über VPN
      # Eingehende Verbindungen für lokale Discovery und Datenübertragung
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -s ${localNetwork.subnet} -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -s ${localNetwork.subnet} -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.discovery} -s ${localNetwork.subnet} -j ACCEPT
      # Eingehende Verbindungen über VPN (für Relay-Verbindungen)
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i proton0 -j ACCEPT
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i tun+ -j ACCEPT
      iptables -A INPUT -p tcp --dport ${toString syncthingPorts.tcp} -i wg+ -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i proton0 -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i tun+ -j ACCEPT
      iptables -A INPUT -p udp --dport ${toString syncthingPorts.quic} -i wg+ -j ACCEPT
      # Ausgehende Verbindungen nur ins Heimnetzwerk
      iptables -A OUTPUT -p tcp --dport ${toString syncthingPorts.tcp} -d ${localNetwork.subnet} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.quic} -d ${localNetwork.subnet} -j ACCEPT
      iptables -A OUTPUT -p udp --dport ${toString syncthingPorts.discovery} -d ${localNetwork.subnet} -j ACCEPT
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

      # 13. FORWARD Chain - Explizit blockieren (Defense-in-Depth)
      # Diese Maschine ist kein Router und sollte nichts forwarden
      iptables -A FORWARD -m limit --limit 1/min --limit-burst 3 -j LOG --log-prefix "FW-FORWARD-BLOCKED: " --log-level 4
      iptables -A FORWARD -j DROP

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
