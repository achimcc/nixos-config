# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Importiert den Home Manager als NixOS Modul
      <home-manager/nixos>
    ];

  # ==========================================
  # SYSTEM BOOT & CORE
  # ==========================================

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device = "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
  networking.hostName = "nixos";
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
      iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT   # OpenVPN TCP / HTTPS API
      iptables -A OUTPUT -p udp --dport 500 -j ACCEPT   # IKEv2
      iptables -A OUTPUT -p udp --dport 4500 -j ACCEPT  # IKEv2 NAT
      
      # 6. DHCP & DNS erlauben (Sonst keine Verbindung zum WLAN/Internet)
      iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT
      iptables -A OUTPUT -p udp --dport 53 -j ACCEPT    # DNS (UDP)
      iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT    # DNS (TCP)
      
      # 7. Lokales Netzwerk erlauben (Optional, falls du Drucker/NAS brauchst)
      # iptables -A OUTPUT -d 192.168.178.0/24 -j ACCEPT
    '';

    # Aufräumen beim Stoppen der Firewall
    extraStopCommands = ''
      iptables -P OUTPUT ACCEPT
      iptables -F OUTPUT
    '';
  };




  # SECURITY: Fallback DNS (verschlüsselt via DNS-over-TLS wird später empfohlen, 
  # aber hier setzen wir neutrale DNS Server statt die des ISPs)
  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];

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
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
  services.pulseaudio.enable = false;
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

  # Ermöglicht der GUI die Kommunikation mit dem NetworkManager über DBus
  services.dbus.enable = true;
  # Wichtig für die Integration in die GNOME Shell
  services.gnome.core-shell.enable = true;

  # 2. Udev Pakete für GUI-Elemente
  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  #==========================================
  # Hack Nerd Font Mono für Nushell
  #==========================================

  fonts.packages = with pkgs; [
    nerd-fonts.hack
  ];

  # ==========================================
  # USER & PACKAGES
  # ==========================================

  # Define a user account.
  users.users.achim = {
    isNormalUser = true;
    description = "Achim Schneider";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
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
  # HOME MANAGER KONFIGURATION
  # ==========================================

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Start des Home-Manager Blocks für User "achim"
  home-manager.users.achim = { pkgs, ... }: {

    home.stateVersion = "24.11";

    # WICHTIG FÜR RUST:
    home.sessionPath = [ "$HOME/.cargo/bin" ];

    # User-spezifische Pakete
    home.packages = with pkgs; [

      # --- VPN & NETZWERK SICHERHEIT ---
      protonvpn-gui # Die grafische Oberfläche für ProtonVPN
      # Hinweis: Beim ersten Start wirst du nach dem Keyring-Passwort gefragt.
      # Das ist normal (Gnome Keyring speichert deine Proton-Zugangsdaten sicher).

      # --- SICHERHEIT & TOOLS ---
      keepassxc
      kdePackages.kleopatra

      # --- NIX ENTWICKLUNG ---
      nil
      nixpkgs-fmt

      # --- RUST ENTWICKLUNG ---
      rustup
      gcc
      # ----- Signal
      signal-desktop
      opencode
    ];

    # --- PGP KONFIGURATION ---
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-gnome3;
      enableSshSupport = true;
    };

    # --- EMAIL CLIENT (Thunderbird - Hardened) ---
    programs.thunderbird = {
      enable = true;
      profiles = {
        "achim" = {
          isDefault = true;
          settings = {
            "privacy.donottrackheader.enabled" = true;
            "mailnews.message_display.disable_remote_image" = true;
            "datareporting.healthreport.uploadEnabled" = false;
            "datareporting.policy.dataSubmissionEnabled" = false;
            "toolkit.telemetry.enabled" = false;
            "javascript.enabled" = false;
            "mailnews.display.html_as" = 3;
          };
        };
      };
    };

    # --- GIT ---
    programs.git = {
      enable = true;
      userName = "Achim Schneider";
      userEmail = "achim.schneider@posteo.de";
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    # --- VS CODE ---
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;

      profiles.default = {
        extensions = with pkgs.vscode-extensions; [
          jnoortheen.nix-ide
          rust-lang.rust-analyzer
          tamasfe.even-better-toml
          vadimcn.vscode-lldb
        ];

        userSettings = {
          # -- NIX --
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nil";
          "nix.serverSettings" = {
            "nil" = {
              "formatting" = {
                "command" = [ "nixpkgs-fmt" ];
              };
            };
          };
          "editor.formatOnSave" = true;

          # -- RUST --
          "rust-analyzer.check.command" = "clippy";
          "rust-analyzer.server.path" = "rust-analyzer";
          "lldb.executable" = "lldb";

          # VS Code Terminal
          "terminal.integrated.defaultProfile.linux" = "nushell";
          "terminal.integrated.profiles.linux" = {
            "nushell" = {
              "path" = "${pkgs.nushell}/bin/nu";
            };
          };
          "terminal.integrated.fontFamily" = "'Hack Nerd Font Mono'";
        };
      };
    };

    # --- BROWSER (LibreWolf) ---
    programs.librewolf = {
      enable = true;
      settings = {
        "privacy.clearOnShutdown.history" = false;
        "privacy.resistFingerprinting" = false; # Manchmal nötig für Streaming/Captchas
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.sessions" = false;
        "browser.startup.page" = 3;
        "xpinstall.signatures.required" = false;
      };

      policies = {
        ExtensionSettings = {
          # KeePassXC
          "keepassxc-browser@keepassxc.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
          };
        };
      };
    };

    # Browser-Integration für KeePassXC
    home.file.".librewolf/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".source =
      "${pkgs.keepassxc}/share/mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json";

    # --- SHELL CONFIGURATION ---

    programs.starship = {
      enable = true;
      enableNushellIntegration = true;
    };

    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
    };

    programs.nushell = {
      enable = true;
      shellAliases = {
        ll = "ls -l";
        la = "ls -a";
        gs = "git status";
        gc = "git commit";
        gp = "git push";
      };
      environmentVariables = {
        EDITOR = "nano";
      };
      extraConfig = ''
        $env.config.show_banner = false
      '';
    };


    # AUTORUN: ProtonVPN beim Login starten
    xdg.configFile."autostart/protonvpn-autostart.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=ProtonVPN AutoStart
      Comment=Startet ProtonVPN beim Systemstart
      Exec=protonvpn-app
      Icon=proton-vpn-logo
      Terminal=false
      Categories=Network;Security;
      X-GNOME-Autostart-enabled=true
    '';

  }; # ENDE HOME-MANAGER BLOCK

  # This valu204459e determines the NixOS release...
  system.stateVersion = "24.11";

}
