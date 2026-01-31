# GNOME Desktop Umgebung
# Wayland, GDM, GNOME Shell mit reduzierten Standard-Apps

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WAYLAND & DISPLAY MANAGER
  # ==========================================

  services.xserver = {
    enable = true; # Nötig für GDM/GNOME-Infrastruktur + XWayland-Kompatibilität
    displayManager.gdm.enable = true;
    displayManager.gdm.wayland = true;
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

  # Electron-Apps nativ auf Wayland (global statt pro Firejail-Wrapper)
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

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
