# Netzwerk & DNS Konfiguration
# NetworkManager für WLAN/Ethernet/VPN mit deklarativem Home-Netzwerk via sops

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NETZWERK GRUNDKONFIGURATION
  # ==========================================

  networking = {
    hostName = "achim-laptop";
    enableIPv6 = false;

    # NetworkManager für alles (WLAN, Ethernet, VPN)
    networkmanager = {
      enable = true;
      # Zufällige MAC-Adresse beim Scannen (erschwert Tracking)
      wifi.scanRandMacAddress = true;
      # Zufällige MAC-Adresse bei jeder Verbindung
      wifi.macAddress = "random";
      ethernet.macAddress = "random";
      # NetworkManager nutzt systemd-resolved
      dns = "systemd-resolved";
      
      # Deklaratives Home-Netzwerk (wird automatisch verbunden)
      ensureProfiles = {
        environmentFiles = [ config.sops.templates."nm-wifi-env".path ];
        profiles = {
          "Greenside4" = {
            connection = {
              id = "Greenside4";
              type = "wifi";
              autoconnect = true;
              autoconnect-priority = 100;
            };
            wifi = {
              ssid = "Greenside4";
              mode = "infrastructure";
            };
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = "$WIFI_HOME_PSK";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              method = "disabled";
            };
          };
        };
      };
    };
  };

  # IPv6 komplett deaktivieren auf Kernel-Ebene
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
    "net.ipv6.conf.lo.disable_ipv6" = 1;
  };

  # ==========================================
  # DNS-OVER-TLS VIA SYSTEMD-RESOLVED
  # ==========================================

  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade"; # "true" kann Probleme machen
    domains = [ "~." ];
    dnsovertls = "true";
    # Kein fallbackDns - verhindert DNS-Leaks wenn VPN down
    # Mullvad DNS-over-TLS (No-Log Policy, schwedisches Recht)
    # https://mullvad.net/en/help/dns-over-https-and-dns-over-tls
    extraConfig = ''
      DNS=194.242.2.2#dns.mullvad.net
    '';
  };

  # ==========================================
  # FIREJAIL SANDBOX
  # ==========================================

  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      tor-browser = {
        executable = "${pkgs.tor-browser}/bin/tor-browser";
        profile = "${pkgs.firejail}/etc/firejail/tor-browser_en-US.profile";
        extraArgs = [
          "--private=/home/achim/Downloads"
        ];
      };
    };
  };

  # Tor Browser Paket
  environment.systemPackages = with pkgs; [
    tor-browser
  ];
}
