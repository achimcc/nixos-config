# Netzwerk & DNS Konfiguration
# NetworkManager für WLAN/Ethernet/VPN mit deklarativem Home-Netzwerk via sops

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NETZWERK GRUNDKONFIGURATION
  # ==========================================

  networking = {
    hostName = "achim-laptop";
    enableIPv6 = true;

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
              method = "auto";
            };
          };
        };
      };
    };
  };

  # IPv6 Privacy Extensions (temporäre Adressen gegen Tracking)
  # net.ipv6.conf.default.use_tempaddr wird bereits von NixOS gesetzt (enableIPv6 = true)
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.use_tempaddr" = 2;
  };

  # ==========================================
  # DNS-OVER-TLS VIA SYSTEMD-RESOLVED
  # ==========================================

  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade"; # "true" kann Probleme machen
    domains = [ "~." ];
    dnsovertls = "opportunistic"; # "true" blockiert VPN-DNS ohne TLS-Support
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

  # Librewolf-spezifische Firejail-Konfiguration
  environment.etc."firejail/librewolf.local".text = ''
    # Bitwarden Desktop Native Messaging (Browser-Biometrics)
    # desktop_proxy läuft als Subprocess im Sandbox und kommuniziert
    # mit der Bitwarden Desktop-App via IPC-Socket in ~/.cache/com.bitwarden.desktop/
    ignore private-tmp
    noblacklist ''${HOME}/.librewolf/native-messaging-hosts

    # Bitwarden Desktop IPC-Socket (desktop_proxy → Desktop-App)
    noblacklist ''${HOME}/.cache/com.bitwarden.desktop
    whitelist ''${HOME}/.cache/com.bitwarden.desktop

    # Nix-Store Zugriff für desktop_proxy Binary
    noblacklist /nix/store

    # D-Bus Zugriff für Bitwarden Desktop IPC und Portal-Integration
    ignore dbus-user none
    ignore dbus-system none

    dbus-user filter
    dbus-user.talk org.freedesktop.portal.*
    dbus-user.talk org.freedesktop.Notifications

    # System D-Bus für Polkit (Fingerprint-Authentifizierung)
    dbus-system filter
    dbus-system.talk org.freedesktop.PolicyKit1

    # FIDO2/WebAuthn Zugriff für Nitrokey (braucht /dev/hidraw*)
    ignore private-dev
    ignore nou2f
  '';

  # Spotify-spezifische Firejail-Konfiguration
  environment.etc."firejail/spotify.local".text = ''
    # Spotify braucht Zugriff auf eigene Binaries und Configs
    ignore private-bin
    ignore private-etc

    # D-Bus: MPRIS (Media-Controls), Notifications, Secrets (OAuth), Portal (Browser-Login)
    ignore dbus-user none
    dbus-user filter
    dbus-user.own org.mpris.MediaPlayer2.spotify
    dbus-user.talk org.freedesktop.Notifications
    dbus-user.talk org.freedesktop.secrets
    dbus-user.talk org.freedesktop.portal.*
  '';

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

      # Signal Desktop - via Flatpak (siehe home-achim.nix)

      # LibreWolf - Privacy Browser mit Sandbox
      librewolf = {
        executable = "${pkgs.librewolf}/bin/librewolf";
        profile = "${pkgs.firejail}/etc/firejail/librewolf.profile";
      };

      # FreeTube - YouTube-Client mit Sandbox
      freetube = {
        executable = "${pkgs.freetube}/bin/freetube";
        profile = "${pkgs.firejail}/etc/firejail/freetube.profile";
        extraArgs = [
          "--env=NIXOS_OZONE_WL=1"
        ];
      };

      # Thunderbird - E-Mail-Client mit Sandbox
      thunderbird = {
        executable = "${pkgs.thunderbird}/bin/thunderbird";
        profile = "${pkgs.firejail}/etc/firejail/thunderbird.profile";
      };

      # KeePassXC - Passwort-Manager mit Sandbox
      keepassxc = {
        executable = "${pkgs.keepassxc}/bin/keepassxc";
        profile = "${pkgs.firejail}/etc/firejail/keepassxc.profile";
      };

      # Newsflash - RSS-Reader mit Sandbox
      newsflash = {
        executable = "${pkgs.newsflash}/bin/newsflash";
        profile = "${pkgs.firejail}/etc/firejail/newsflash.profile";
      };

      # Logseq - Wissensmanagement (Electron-App)
      # Nutzt Obsidian-Profil da kein eigenes Logseq-Profil existiert
      logseq = {
        executable = "${pkgs.logseq}/bin/logseq";
        profile = "${pkgs.firejail}/etc/firejail/obsidian.profile";
        extraArgs = [
          "--env=NIXOS_OZONE_WL=1"
          "--whitelist=/home/achim/Dokumente/Logseq"
        ];
      };

      # VSCodium - Code Editor (Electron-App)
      vscodium = {
        executable = "${pkgs.vscodium}/bin/codium";
        profile = "${pkgs.firejail}/etc/firejail/vscodium.profile";
        extraArgs = [
          "--env=NIXOS_OZONE_WL=1"
          "--whitelist=/home/achim/Projects"
          "--whitelist=/home/achim/nixos-config"
        ];
      };

      # Zathura - PDF-Viewer mit Sandbox
      zathura = {
        executable = "${pkgs.zathura}/bin/zathura";
        profile = "${pkgs.firejail}/etc/firejail/zathura.profile";
      };

      # Discord - Chat-Client mit Sandbox
      discord = {
        executable = "${pkgs.discord}/bin/discord";
        profile = "${pkgs.firejail}/etc/firejail/discord.profile";
        extraArgs = [
          "--env=NIXOS_OZONE_WL=1"
        ];
      };

      # Flare - Signal-Client via Flatpak (eigene Bubblewrap-Sandbox)

      # Spotify - Musik-Streaming mit Sandbox
      spotify = {
        executable = "${pkgs.spotify}/bin/spotify";
        profile = "${pkgs.firejail}/etc/firejail/spotify.profile";
      };
    };
  };

  # Pakete die von Firejail gewrappt werden
  # (Thunderbird, KeePassXC, Newsflash, Zathura, VSCodium sind in home-achim.nix)
  # Signal via Flatpak (home-achim.nix), nicht mehr hier
  environment.systemPackages = with pkgs; [
    tor-browser
    librewolf
    freetube
    logseq
    discord
    spotify
  ];
}
