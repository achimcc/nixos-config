# NixOS Hauptkonfiguration für achim-laptop
# Module werden aus ./modules/ importiert

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/network.nix
    ./modules/firewall.nix
    ./modules/firewall-zones.nix
    ./modules/protonvpn.nix
    ./modules/desktop.nix
    ./modules/audio.nix
    ./modules/power.nix
    ./modules/sops.nix
    ./modules/security.nix
    ./modules/secureboot.nix
    ./modules/suricata.nix
    ./modules/logwatch.nix
  ];

  # ==========================================
  # BOOTLOADER (Secure Boot via Lanzaboote in modules/secureboot.nix)
  # ==========================================

  boot.kernelParams = [ "intel_iommu=on" "iommu=force" ];
  boot.loader.systemd-boot.configurationLimit = 10; # Weniger Boot-Einträge
  boot.loader.efi.canTouchEfiVariables = true;

  # ==========================================
  # LUKS Verschlüsselung mit FIDO2 (Nitrokey 3C NFC)
  # ==========================================

  # Systemd in Initrd für FIDO2 LUKS-Entsperrung
  boot.initrd.systemd.enable = true;

  # TPM 2.0 für zusätzliche Boot-Sicherheit
  boot.initrd.systemd.tpm2.enable = true;

  # Root-Partition: FIDO2 mit Passwort-Fallback
  boot.initrd.luks.devices."luks-fcef0557-8a09-4f30-b78e-aecc458a975a".crypttabExtraOpts = [
    "fido2-device=auto"
  ];

  # Swap: FIDO2 mit Passwort-Fallback
  # Swap-Verschlüsselung explizit verifiziert (LUKS2)
  # Swap ist in LUKS-Container, wird über FIDO2 entsperrt
  # Keine separaten swapDevices nötig - bereits in hardware-configuration.nix definiert
  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device =
    "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".crypttabExtraOpts = [
    "fido2-device=auto"
  ];
  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".allowDiscards = true; # TRIM für SSD

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
    extraGroups = [ "networkmanager" "wheel" "input" ];
    shell = pkgs.nushell;
  };

  # ==========================================
  # SYSTEM PAKETE
  # ==========================================

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "python3.12-ecdsa-0.19.1" # pynitrokey-Abhängigkeit, CVE-2024-23342 (Timing-Side-Channel, lokal irrelevant)
  ];

  environment.systemPackages = with pkgs; [
    git
    nushell
    libsecret
    nano # Für EDITOR Variable in nushell
    vim
    python3
  ];

  # ==========================================
  # FIRMWARE
  # ==========================================

  hardware.enableRedistributableFirmware = true;

  # ==========================================
  # BLUETOOTH
  # ==========================================

  # ==========================================
  # NITROKEY 3C NFC
  # ==========================================

  hardware.nitrokey.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.bluetooth.settings = {
    General = {
      Experimental = true;
    };
  };

  # Lade uhid-Modul für Bluetooth HID-Geräte (Mäuse, Tastaturen)
  boot.kernelModules = [ "uhid" ];

  # ==========================================
  # DRUCKER (Brother MFC-7360N im Netzwerk)
  # ==========================================

  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ]; # Open-Source Brother Laser Treiber
  };

  # Netzwerk-Drucker Auto-Discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    # ANONYMITÄT: Kein Hostname/Service-Broadcasting im Netzwerk
    publish = {
      enable = false;       # Kein Hostname/Service-Publishing
      addresses = false;    # Keine IP-Adressen publishen
      workstation = false;  # Nicht als Workstation ankündigen
      domain = false;       # Keine Domain ankündigen
    };
  };

  # ==========================================
  # FLATPAK (für Signal Desktop - braucht keine User Namespaces)
  # ==========================================

  services.flatpak.enable = true;

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
    flags = [
      "--update-input" "nixpkgs"
      "--update-input" "nixpkgs-unstable"
    ];
  };

  # ==========================================
  # ZUSÄTZLICHE CA-ZERTIFIKATE
  # ==========================================

  # Signal Messenger nutzt eigene Root-CA für chat.signal.org
  # Siehe: https://github.com/signalapp/Signal-Desktop/issues/6707
  security.pki.certificateFiles = [
    ./ca-certificates/signal-messenger.pem
  ];

  # ==========================================
  # STATE VERSION - NICHT ÄNDERN!
  # ==========================================

  system.stateVersion = "24.11";
}
