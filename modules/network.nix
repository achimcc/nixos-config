# Netzwerk & DNS Konfiguration
# wpa_supplicant für WLAN, NetworkManager für Ethernet, systemd-resolved mit DNS-over-TLS

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NETZWERK GRUNDKONFIGURATION
  # ==========================================

  networking = {
    hostName = "achim-laptop";
    enableIPv6 = false;

    # ==========================================
    # DEKLARATIVE WLAN-KONFIGURATION MIT SOPS
    # ==========================================

    wireless = {
      enable = true;
      # Secrets aus sops-nix Template (key=value Format)
      secretsFile = config.sops.templates."wpa_supplicant.conf".path;
      # Bekannte WLAN-Netzwerke
      networks = {
        "Greenside4" = {
          pskRaw = "ext:wifi_home_psk";
        };
      };
      # Erlaube Konfiguration über wpa_cli
      userControlled.enable = true;
      # Nur bekannte Netzwerke erlauben (Sicherheit)
      extraConfig = ''
        ctrl_interface=/run/wpa_supplicant
        ctrl_interface_group=wheel
      '';
    };

    # NetworkManager für Ethernet und VPN (WLAN wird von wpa_supplicant verwaltet)
    networkmanager = {
      enable = true;
      # WLAN wird von wpa_supplicant verwaltet, nicht NetworkManager
      unmanaged = [ "type:wifi" ];
      # Zufällige MAC-Adresse für Ethernet
      ethernet.macAddress = "random";
      # NetworkManager nutzt systemd-resolved
      dns = "systemd-resolved";
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
    extraConfig = ''
      DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
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
