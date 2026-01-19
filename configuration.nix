# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Home Manager wird jetzt via flake.nix importiert
    ];

  # ==========================================
  # SYSTEM BOOT & CORE
  # ==========================================

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device = "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
  networking.hostName = "achim-laptop";
  networking.enableIPv6 = false;

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
    "net.ipv6.conf.lo.disable_ipv6" = 1;
  };

  # ==========================================
  # NETZWERK & SICHERHEIT (System-Level)
  # ==========================================

  # Enable networking
  networking.networkmanager = {
    enable = true;
    # SECURITY: Zufällige MAC-Adresse beim Scannen nach WLANs (erschwert Tracking)
    wifi.scanRandMacAddress = true;
  };
  # Firejail auf Systemebene aktivieren, um Wrapper zu erstellen
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      tor-browser = {
        # Wir referenzieren das Paket direkt aus den System-Pkgs
        executable = "${pkgs.tor-browser}/bin/tor-browser";
        profile = "${pkgs.firejail}/etc/firejail/tor-browser_en-US.profile";
        extraArgs = [
          # Hardcoded Pfad, um Rekursionsfehler zu vermeiden
          "--private=/home/achim/Downloads"
        ];
      };
    };
  };

  # ==========================================
  # HARDENED FIREWALL / KILL SWITCH
  # ==========================================

  networking.firewall = {
    enable = true;
    checkReversePath = "loose"; # Wichtig für WireGuard/ProtonVPN

    # Hier erlauben wir ausgehende Verbindungen für VPN-Handshake und DNS
    extraCommands = ''
      # ==========================================
      # IPv4 REGELN
      # ==========================================
      
      # 1. Alles löschen & Standard auf DROP setzen
      iptables -F OUTPUT
      iptables -P OUTPUT DROP
      
      # 2. Loopback erlauben (Lokale Prozesse)
      iptables -A OUTPUT -o lo -j ACCEPT
      
      # 3. Bestehende Verbindungen erlauben
      iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      
      # 4. VPN Interfaces erlauben (Hier darf alles raus!)
      # proton0 = Proton App Interface, tun+ = OpenVPN, wg+ = WireGuard
      iptables -A OUTPUT -o proton0 -j ACCEPT
      iptables -A OUTPUT -o tun+ -j ACCEPT
      iptables -A OUTPUT -o wg+ -j ACCEPT
      
      # 5. WICHTIG: Erlaube den Verbindungsaufbau zum VPN (Physical Interface)
      # Wir erlauben UDP/TCP auf gängigen VPN Ports
      iptables -A OUTPUT -p udp --dport 51820 -j ACCEPT # WireGuard
      iptables -A OUTPUT -p udp --dport 1194 -j ACCEPT  # OpenVPN UDP
      iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT   # HTTPS API
      iptables -A OUTPUT -p udp --dport 443 -j ACCEPT   # Stealth Protocol
      iptables -A OUTPUT -p udp --dport 500 -j ACCEPT   # IKEv2
      iptables -A OUTPUT -p udp --dport 4500 -j ACCEPT  # IKEv2 NAT
      
      # 6. DHCP erlauben (Sonst keine Verbindung zum WLAN)
      iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT
      
      # 7. DNS NUR über systemd-resolved (127.0.0.53) - verhindert DNS-Leaks
      iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.53 -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.53 -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 853 -d 127.0.0.53 -j ACCEPT
      
      # 7. Lokales Netzwerk erlauben (Optional, falls du Drucker/NAS brauchst)
      # iptables -A OUTPUT -d 192.168.178.0/24 -j ACCEPT

      # ==========================================
      # IPv6 REGELN - Alles blockieren (IPv6 ist deaktiviert)
      # ==========================================
      
      # Alle Chains auf DROP setzen
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

    # Aufräumen beim Stoppen der Firewall
    extraStopCommands = ''
      # IPv4 aufräumen
      iptables -P OUTPUT ACCEPT
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




  # SECURITY: DNS-over-TLS via systemd-resolved
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade"; # "true" kann Probleme machen, das ist sicherer
    domains = [ "~." ];
    dnsovertls = "true"; # Versucht TLS, fällt auf unverschlüsselt zurück wenn nötig
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
    extraConfig = ''
      DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
    '';
  };

  # NetworkManager soll resolved nutzen
  networking.networkmanager.dns = "systemd-resolved";

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "de_DE.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # ==========================================
  # DESKTOP & DISPLAY
  # ==========================================

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # GNOME Bloat entfernen (du nutzt LibreWolf, Thunderbird, etc.)
  environment.gnome.excludePackages = with pkgs; [
    epiphany       # GNOME Browser - du nutzt LibreWolf
    geary          # Mail Client - du nutzt Thunderbird
    gnome-music    # Musik Player
    gnome-tour     # Willkommens-Tour
    totem          # Video Player
    yelp           # Hilfe-Viewer
    gnome-contacts # Kontakte
    gnome-maps     # Karten
    gnome-weather  # Wetter
    simple-scan    # Scanner (falls du keinen hast)
  ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  # services.pulseaudio.enable = false; # Nicht mehr nötig in 24.11
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ==========================================
  # SYSTEM-DIENSTE FÜR PROTONVPN FIX
  # ==========================================

  # 1. Keyring Dienst aktivieren (Damit der Login gespeichert werden kann)
  services.gnome.gnome-keyring.enable = true;

  # Wichtig für die Integration in die GNOME Shell
  services.gnome.core-shell.enable = true;

  # 2. Udev Pakete für GUI-Elemente
  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  #==========================================
  # Hack Nerd Font Mono für Nushell
  #==========================================

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "Hack" ]; })
  ];

  # ==========================================
  # USER & PACKAGES
  # ==========================================

  # Define a user account.
  users.users.achim = {
    isNormalUser = true;
    description = "Achim Schneider";
    extraGroups = [ "networkmanager" "wheel" ];
    # Nushell als Standard-Login-Shell setzen
    shell = pkgs.nushell;
  };

  # Allow unfree packages (notwendig für ProtonVPN, Codecs, etc.)
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    git
    nushell # Nushell muss auch global verfügbar sein

    # GNOME Extensions für besseren Tray-Icon Support (wichtig für ProtonVPN GUI)
    gnomeExtensions.appindicator
    libsecret
    iptables
    tor-browser
  ];

  # ==========================================
  # NIX FLAKES AKTIVIEREN
  # ==========================================

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ==========================================
  # AUTOMATISCHE UPDATES & WARTUNG
  # ==========================================

  # Automatische System-Updates (täglich um 4:00 Uhr)
  system.autoUpgrade = {
    enable = true;
    allowReboot = false; # Kein automatischer Reboot - du entscheidest wann
    dates = "04:00";
    flake = "/home/achim/nixos-config#achim-laptop";
  };

  # Garbage Collection - alte Generationen automatisch löschen
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Store optimieren - Deduplizierung von Dateien
  nix.settings.auto-optimise-store = true;

  # This value determines the NixOS release...
  system.stateVersion = "24.11";

}
