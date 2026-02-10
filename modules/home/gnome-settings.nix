# GNOME Dconf Settings
# Deklarative Desktop-Einstellungen für GNOME

{ config, lib, pkgs, ... }:

{
  # Dconf aktivieren
  dconf.enable = true;

  # GNOME Settings via Home Manager
  dconf.settings = {
    # ==========================================
    # ERSCHEINUNGSBILD
    # ==========================================

    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      clock-show-weekday = true;
      clock-show-seconds = false;
    };

    "org/gnome/desktop/background" = {
      picture-options = "zoom";
    };

    # ==========================================
    # TASTATUR & EINGABE
    # ==========================================

    "org/gnome/desktop/input-sources" = {
      sources = [ (lib.hm.gvariant.mkTuple [ "xkb" "de" ]) ];
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = true;
      two-finger-scrolling-enabled = true;
      natural-scroll = true;
    };

    # ==========================================
    # FENSTER & WORKSPACES
    # ==========================================

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
      focus-mode = "click";
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      edge-tiling = true;
    };

    "org/gnome/shell" = {
      favorite-apps = [
        "org.wezfurlong.wezterm.desktop"
        "librewolf.desktop"
        "thunderbird.desktop"
        "org.gnome.Nautilus.desktop"
        "code.desktop"
        "org.keepassxc.KeePassXC.desktop"
        "signal-desktop.desktop"
      ];
      # Extensions aktivieren
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "pano@elhan.io"
      ];
    };

    # ==========================================
    # PRIVACY & SICHERHEIT
    # ==========================================

    "org/gnome/desktop/privacy" = {
      remember-recent-files = true;
      recent-files-max-age = 30;
      remove-old-trash-files = true;
      remove-old-temp-files = true;
      old-files-age = 14; # Tage
    };

    "org/gnome/desktop/notifications" = {
      show-in-lock-screen = false;
    };

    "org/gnome/desktop/session" = {
      idle-delay = 300; # Bildschirmschoner nach 5 Minuten Inaktivität
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = true;
      lock-delay = 0; # Sofort sperren wenn Screensaver aktiv
    };

    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
      sleep-inactive-battery-type = "suspend";
      sleep-inactive-battery-timeout = 900; # 15 Minuten
      power-button-action = "interactive";
    };

    # ==========================================
    # NAUTILUS (Dateimanager)
    # ==========================================

    "org/gnome/nautilus/preferences" = {
      default-folder-viewer = "list-view";
      show-hidden-files = false;
    };

    "org/gnome/nautilus/list-view" = {
      default-zoom-level = "small";
    };

    # ==========================================
    # TASTENKÜRZEL
    # ==========================================

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Terminal";
      command = "kgx"; # GNOME Console
      binding = "<Super>Return";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      name = "Screenshot (Swappy)";
      command = "sh -c 'grim -g \"$(slurp)\" - | swappy -f -'";
      binding = "<Control>Print";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      name = "Posteo TOTP";
      command = "/home/achim/.local/bin/totp-posteo";
      binding = "<Super><Shift>t";
    };

    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Super>q" ];
      toggle-fullscreen = [ "<Super>f" ];
      switch-to-workspace-left = [ "<Super>Left" ];
      switch-to-workspace-right = [ "<Super>Right" ];
    };
  };
}
