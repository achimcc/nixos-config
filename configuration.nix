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

  # ==========================================
  # NETZWERK & SICHERHEIT (System-Level)
  # ==========================================

  # Enable networking
  networking.networkmanager = {
    enable = true;
    # SECURITY: Zufällige MAC-Adresse beim Scannen nach WLANs (erschwert Tracking)
    wifi.scanRandMacAddress = true;
  };

  networking.firewall = {
    enable = true;
    # Wir lassen keine Ports offen (maximale Sicherheit für Desktop)
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    # Wichtig für VPN:
    checkReversePath = "loose";
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

  # 2. Udev Pakete für GUI-Elemente
  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

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

  }; # ENDE HOME-MANAGER BLOCK

  # This value determines the NixOS release...
  system.stateVersion = "24.11";

}
