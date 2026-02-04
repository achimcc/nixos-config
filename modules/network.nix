# Netzwerk & DNS Konfiguration
# NetworkManager für WLAN/Ethernet/VPN mit deklarativem Home-Netzwerk via sops

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # NETZWERK GRUNDKONFIGURATION
  # ==========================================

  networking = {
    # Generischer Hostname (wird nicht im Netzwerk gebroadcastet)
    hostName = "nixos";
    # SICHERHEIT: IPv6 deaktiviert (verhindert VPN-Bypass und IPv6-Leaks)
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

      # ANONYMITÄT: Kein Hostname im DHCP senden
      dhcp = "internal";

      # NetworkManager Dispatcher: Hostname nicht senden
      dispatcherScripts = [
        {
          source = pkgs.writeText "no-hostname" ''
            # Verhindert, dass Hostname im DHCP gesendet wird
            if [ "$2" = "dhcp4-change" ] || [ "$2" = "dhcp6-change" ]; then
              exit 0
            fi
          '';
          type = "basic";
        }
      ];

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

  # IPv6 auf Kernel-Ebene deaktivieren (zusätzliche Absicherung)
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
    dnssec = "true";
    domains = [ "~." ];
    dnsovertls = "true";

    # SICHERHEIT: Kein Fallback-DNS (verhindert DNS-Leaks wenn VPN down)
    fallbackDns = [];  # Explizit leer - keine Fallback-DNS-Server

    # Quad9 DNS-over-TLS (Non-Profit, Schweizer Recht, Malware-Blocking)
    # https://www.quad9.net/service/service-addresses-and-features
    extraConfig = ''
      DNS=9.9.9.9#dns.quad9.net
      # Fallback explizit deaktivieren
      FallbackDNS=
      # DNS-Anfragen nur über spezifizierten Server
      DNSStubListener=yes
      # DNS-Cache auf Minimum (verhindert Stale Entries)
      Cache=no-negative
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

    # Wayland Clipboard Zugriff (wl-copy/wl-paste für TOTP)
    # Erlaubt Paste von System-Clipboard (z.B. TOTP-Codes)
    noblacklist /run/user/1000
    whitelist /run/user/1000/wayland-*

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

  # Thunderbird-spezifische Firejail-Konfiguration
  environment.etc."firejail/thunderbird.local".text = ''
    # D-Bus Zugriff (erforderlich für pinentry-gnome3 und GNOME Keyring)
    ignore dbus-user none
    ignore dbus-system none

    # D-Bus Session Socket explizit whitelisten
    noblacklist /run/user/1000/bus

    dbus-user filter
    dbus-user.talk org.freedesktop.secrets
    dbus-user.talk org.gnome.keyring.*
    dbus-user.talk org.freedesktop.portal.*
    dbus-user.talk org.gtk.vfs.*
    dbus-user.own org.gnome.gcr.*

    # System D-Bus für Polkit (Smartcard-PIN-Authentifizierung)
    dbus-system filter
    dbus-system.talk org.freedesktop.PolicyKit1

    # OpenPGP/Smartcard Zugriff für Nitrokey (E-Mail-Verschlüsselung)
    # Thunderbird hat native OpenPGP-Unterstützung seit v78
    # Smartcard-Zugriff braucht /dev/hidraw* für Nitrokey
    ignore private-dev
    ignore nou2f

    # Nix-Store Zugriff für GPG-Binary und Abhängigkeiten
    noblacklist /nix/store

    # GPG-Agent Socket Zugriff für Smartcard-PIN-Eingabe
    # Socket liegt in /run/user/1000/gnupg/
    noblacklist /run/user/1000/gnupg
    whitelist /run/user/1000/gnupg

    # GPG Public Key Import (dedizierter Ordner für Key-Austausch)
    noblacklist ''${HOME}/.config/thunderbird-gpg
    whitelist ''${HOME}/.config/thunderbird-gpg

    # Wayland Display Zugriff (GNOME/Wayland Session)
    # Thunderbird-Default-Profil hat "ignore include whitelist-runuser-common.inc"
    # was den Wayland-Socket blockiert. Wir aktivieren die Whitelist wieder:
    ignore ignore include whitelist-runuser-common.inc
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
          "--whitelist=/home/achim/Dokumente/Logseq"
        ];
      };

      # VSCodium - Code Editor (Electron-App)
      vscodium = {
        executable = "${pkgs.vscodium}/bin/codium";
        profile = "${pkgs.firejail}/etc/firejail/vscodium.profile";
        extraArgs = [
          "--whitelist=/home/achim/Projects"
          "--whitelist=/home/achim/nixos-config"
        ];
      };

      # Evince - GNOME PDF-Viewer mit Sandbox
      evince = {
        executable = "${pkgs.evince}/bin/evince";
        profile = "${pkgs.firejail}/etc/firejail/evince.profile";
      };

      # Discord - Chat-Client mit Sandbox
      discord = {
        executable = "${pkgs.discord}/bin/discord";
        profile = "${pkgs.firejail}/etc/firejail/discord.profile";
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
  # Thunderbird: System-Paket (für Desktop-Datei) + Firejail-Wrapper (siehe wrappedBinaries oben)
  # NICHT über home-achim.nix installieren, sonst wird Wrapper überschrieben!
  # (KeePassXC, Newsflash, VSCodium sind in home-achim.nix)
  # Signal via Flatpak (home-achim.nix), nicht mehr hier
  environment.systemPackages = with pkgs; [
    tor-browser
    librewolf
    mullvad-browser  # Maximum Anti-Fingerprinting (Tor Browser ohne Tor)
    freetube
    logseq
    discord
    spotify
    thunderbird
  ];
}
