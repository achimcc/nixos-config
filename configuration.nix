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

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device = "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
  networking.hostName = "nixos"; # Define your hostname.

  # Enable networking
  networking.networkmanager.enable = true;

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

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  # HINWEIS: Syntax aktualisiert (xserver prefix entfernt wie in Warnung empfohlen)
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

  # Define a user account.
  users.users.achim = {
    isNormalUser = true;
    description = "Achim Schneider";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    git
  ];

  # ==========================================
  # HOME MANAGER KONFIGURATION
  # ==========================================

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.achim = { pkgs, ... }: {

    home.stateVersion = "24.11";

    # User-spezifische Pakete
    home.packages = with pkgs; [

      # --- SICHERHEIT & TOOLS ---
      keepassxc

      # FIX: Das Paket heißt "kdePackages.kleopatra"
      kdePackages.kleopatra

      # Tools für Nix-Entwicklung
      nil
      nixpkgs-fmt
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
      # HINWEIS: Syntax für extraConfig hat sich geändert, wenn es Konflikte gibt
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    # --- VS CODE ---
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;

      # HINWEIS: Neue Syntax-Struktur für Home Manager (Warnung behoben)
      profiles.default = {
        extensions = with pkgs.vscode-extensions; [
          jnoortheen.nix-ide
        ];
        userSettings = {
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
        };
      };
    };

    # --- BROWSER (LibreWolf) ---
    programs.librewolf = {
      enable = true;
      settings = {
        "privacy.clearOnShutdown.history" = false;
        "privacy.resistFingerprinting" = false;
      };
      policies = {
        ExtensionSettings = {
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

  };

  # This value determines the NixOS release...
  system.stateVersion = "24.11";

}
