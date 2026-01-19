# GNOME Desktop Umgebung
# X11, GDM, GNOME Shell mit reduzierten Standard-Apps

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # X11 & DISPLAY MANAGER
  # ==========================================

  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    # Tastaturlayout
    xkb = {
      layout = "de";
      variant = "";
    };
  };

  # Konsolen-Tastaturlayout
  console.keyMap = "de";

  # ==========================================
  # GNOME KONFIGURATION
  # ==========================================

  # Bloatware entfernen
  environment.gnome.excludePackages = with pkgs; [
    epiphany       # Browser - LibreWolf wird genutzt
    geary          # Mail - Thunderbird wird genutzt
    gnome-music    # Musik Player
    gnome-tour     # Willkommens-Tour
    totem          # Video Player
    yelp           # Hilfe-Viewer
    gnome-contacts # Kontakte
    gnome-maps     # Karten
    gnome-weather  # Wetter
    simple-scan    # Scanner
  ];

  # GNOME Dienste
  services.gnome = {
    gnome-keyring.enable = true;
    # core-shell wird automatisch durch desktopManager.gnome aktiviert
  };

  # Udev für GUI-Elemente
  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  # ==========================================
  # SYSTEM PAKETE FÜR DESKTOP
  # ==========================================

  environment.systemPackages = with pkgs; [
    wl-clipboard
    gnomeExtensions.appindicator # Tray-Icon Support (wichtig für ProtonVPN)
  ];

  # ==========================================
  # FONTS
  # ==========================================

  fonts.packages = with pkgs; [
    nerd-fonts.hack
  ];
}
