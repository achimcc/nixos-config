# GNOME Desktop Umgebung
# Wayland, GDM, GNOME Shell mit reduzierten Standard-Apps

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WAYLAND & DISPLAY MANAGER
  # ==========================================

  services.xserver = {
    enable = true; # Nötig für XWayland-Kompatibilität

    # Tastaturlayout
    xkb = {
      layout = "de";
      variant = "";
    };
  };

  # Display Manager
  services.displayManager.gdm = {
    enable = true;
    wayland = true;
  };

  # Desktop Manager
  services.desktopManager.gnome.enable = true;

  # ==========================================
  # SWAY - ALTERNATIVE SESSION
  # ==========================================
  # Aktiviert Sway als alternative Window Manager Session in GDM
  # Konfiguration erfolgt in home-manager (modules/home/sway.nix)

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true; # GTK-Themes in Sway
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
    gnome-contacts    # Kontakte
    gnome-maps        # Karten
    gnome-weather     # Wetter
    gnome-characters  # Zeichentabelle — löst GPU HANG (ecode 12:1) → SLUB crash aus
    simple-scan       # Scanner
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

  # Intel i915 Meteor Lake: GPU HANG Workaround (SYSTEM-LEVEL)
  # i915 Render Engine Bug (ecode 12:1) auf Meteor Lake — triggerbar durch jede GPU-Nutzung
  # GSK_RENDERER=gl reicht NICHT: OpenGL nutzt dieselbe Render Engine wie Vulkan
  # Crashes: 2026-02-15 (Nautilus/Vulkan), 2026-02-23 (gnome-characters/Vulkan),
  #          2026-02-27 (gnome-characters/GL, nach Suspend/Resume)
  # cairo = reines CPU-Rendering für GTK4-Widgets. Nicht betroffen: VA-API, Mutter, Browser
  # MUSS auf System-Ebene stehen — home.sessionVariables erreicht Desktop-gestartete Apps NICHT
  environment.sessionVariables.GSK_RENDERER = "cairo";

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
