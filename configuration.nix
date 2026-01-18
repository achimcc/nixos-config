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
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

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
    # Pakete werden jetzt primär über Home Manager verwaltet (siehe unten)
    packages = with pkgs; [ ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wl-clipboard # Wichtig für Copy-Paste im Terminal
    git # Empfohlen für VS Code Git-Features
  ];

  # ==========================================
  # HOME MANAGER KONFIGURATION
  # ==========================================

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.achim = { pkgs, ... }: {

    # Version sollte mit system.stateVersion übereinstimmen
    home.stateVersion = "24.11";

    # User-spezifische Pakete
    home.packages = with pkgs; [
      librewolf

      # --- SICHERHEIT ---
      keepassxc # Der empfohlene Passwortmanager (Offline, Open Source)

      # Tools für Nix-Entwicklung (werden von VS Code genutzt)
      nil # Der Language Server (Autokorrektur)
      nixpkgs-fmt # Formatierung
    ];

    programs.git = {
      enable = true;
      userName = "Achim Schneider";
      userEmail = "achim.schneider@posteo.de";

      # Optional: Nützliche Extras
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    # VS Code Konfiguration
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;

      # Extensions automatisch installieren
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide # Das Nix Plugin
        # mkhl.direnv        # Optional: Sehr gut für Nix-Umgebungen
      ];

      # Settings.json automatisch schreiben
      userSettings = {
        # Aktiviert den Language Server für Nix Dateien
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix.serverSettings" = {
          "nil" = {
            "formatting" = {
              "command" = [ "nixpkgs-fmt" ];
            };
          };
        };
        # Optional: Formatieren beim Speichern
        "editor.formatOnSave" = true;
      };
    };
  };

  # This value determines the NixOS release...
  system.stateVersion = "24.11";

}
