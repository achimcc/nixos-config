# Netzwerk & DNS Konfiguration
# NetworkManager, systemd-resolved mit DNS-over-TLS, IPv6 deaktiviert

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NETZWERK GRUNDKONFIGURATION
  # ==========================================

  networking = {
    hostName = "nixos";
    enableIPv6 = false;

    networkmanager = {
      enable = true;
      # Zufällige MAC-Adresse beim Scannen (erschwert Tracking)
      wifi.scanRandMacAddress = true;
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
          "--private=/home/user/Downloads"
        ];
      };
    };
  };

  # Tor Browser Paket
  environment.systemPackages = with pkgs; [
    tor-browser
    nftables
  ];
}
