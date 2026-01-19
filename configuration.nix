# NixOS Hauptkonfiguration für achim-laptop
# Module werden aus ./modules/ importiert

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/network.nix
    ./modules/firewall.nix
    ./modules/desktop.nix
    ./modules/audio.nix
    ./modules/power.nix
  ];

  # ==========================================
  # BOOTLOADER
  # ==========================================

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10; # Weniger Boot-Einträge
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS Verschlüsselung
  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device = 
    "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";

  # ==========================================
  # LOKALISIERUNG
  # ==========================================

  time.timeZone = "Europe/Berlin";
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
  # BENUTZER
  # ==========================================

  users.users.achim = {
    isNormalUser = true;
    description = "Achim Schneider";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.nushell;
  };

  # ==========================================
  # SYSTEM PAKETE
  # ==========================================

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    nushell
    libsecret
    nano # Für EDITOR Variable in nushell
  ];

  # ==========================================
  # DRUCKER
  # ==========================================

  services.printing.enable = true;

  # ==========================================
  # SSD OPTIMIERUNG
  # ==========================================

  services.fstrim.enable = true;

  # ==========================================
  # NIX EINSTELLUNGEN
  # ==========================================

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    max-jobs = "auto";
    cores = 0; # Alle Kerne nutzen
  };

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ==========================================
  # AUTOMATISCHE UPDATES
  # ==========================================

  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    dates = "04:00";
    flake = "/home/achim/nixos-config#achim-laptop";
  };

  # ==========================================
  # STATE VERSION - NICHT ÄNDERN!
  # ==========================================

  system.stateVersion = "24.11";
}
