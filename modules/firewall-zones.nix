# Netzwerk-Segmentierung via Firewall-Zonen
# Definiert Vertrauensstufen für verschiedene Netzwerk-Bereiche

{ config, lib, pkgs, ... }:

let
  # Netzwerk-Zonen mit Vertrauensstufen
  zones = {
    # Höchstes Vertrauen: Localhost
    trusted = {
      sources = [ "127.0.0.0/8" "::1/128" ];
      allowAll = true;
    };

    # Mittleres Vertrauen: Heimnetzwerk (mit Einschränkungen)
    home = {
      sources = [ "192.168.178.0/24" "fe80::/10" ];
      allowedPorts = {
        tcp = [ 22000 ];  # Syncthing
        udp = [ 21027 22000 ];  # Syncthing Discovery + QUIC
      };
      allowedHosts = [
        "192.168.178.1"  # Router (Gateway)
      ];
    };

    # Niedriges Vertrauen: VPN-Tunnel
    vpn = {
      sources = [ "10.2.0.0/24" ];  # ProtonVPN WireGuard Range
      interfaces = [ "proton0" "tun+" "wg+" ];
      allowAll = true;  # Über VPN ist alles erlaubt
    };

    # Kein Vertrauen: Internet (Default Deny, außer VPN-Verbindungsaufbau)
    internet = {
      sources = [ "0.0.0.0/0" "::/0" ];
      allowAll = false;
    };
  };
in
{
  # Dokumentation der Zonen-Architektur
  # Diese Datei definiert nur die Zonen-Struktur
  # Die tatsächlichen iptables-Regeln bleiben in firewall.nix
  #
  # Zonen-Hierarchie:
  # 1. trusted (localhost) - volle Rechte
  # 2. vpn (VPN-Tunnel) - volle Rechte
  # 3. home (Heimnetzwerk) - eingeschränkte Rechte
  # 4. internet (WAN) - default deny + VPN-Ports

  # Diese Konfiguration dient als Dokumentation und zukünftige Grundlage
  # für eine nftables-Migration mit nativen Zonen-Support

  options = {
    networking.firewall.zones = lib.mkOption {
      type = lib.types.attrs;
      default = zones;
      description = "Firewall zones configuration";
    };
  };

  config = {
    # Zonen werden von firewall.nix verwendet
    networking.firewall.zones = zones;
  };
}
