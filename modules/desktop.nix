# GNOME Desktop Umgebung
# Wayland, GDM, GNOME Shell mit reduzierten Standard-Apps

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # WAYLAND & DISPLAY MANAGER
  # ==========================================

  services.xserver = {
    enable = true; # Nötig für XWayland-Kompatibilität

    # Tastaturlayout: US-Hardware, Umlaute auf der linken Option-/Alt-Taste
    # Opt+a/o/u = ä/ö/ü, Opt+s = ß, mit Shift die Großbuchstaben.
    # Eigenes Layout, weil kein mitgeliefertes us-Variant die Umlaute auf die
    # Buchstaben selbst legt (us(altgr-intl) benutzt q/p/y).
    #
    # Zwei Gruppen, weil zwei Tastaturen im Spiel sind: die NuPhy Air75 ist
    # US-bedruckt, die eingebaute ThinkPad-Tastatur deutsch. Diese Liste gilt
    # für den Anmeldebildschirm und die Konsole — er bietet damit beide an.
    # In der GNOME-Sitzung zählt stattdessen dconf (modules/home/gnome-settings.nix),
    # dort schaltet der Dienst aus modules/home/keyboard-layout-auto.nix um.
    xkb = {
      layout = "us-umlaut,de";
      variant = ",";

      extraLayouts.us-umlaut = {
        description = "English (US, Umlaute auf der linken Option-Taste)";
        languages = [ "eng" "ger" ];
        symbolsFile = pkgs.writeText "us-umlaut-symbols" ''
          // US-Layout, dritte Ebene auf der linken Alt-/Option-Taste.
          // Die rechte Alt bleibt eine gewöhnliche Alt-Taste (Alt+Tab usw.).
          partial alphanumeric_keys
          xkb_symbols "basic" {
              include "us(basic)"
              name[Group1] = "English (US, Umlaute auf Option)";

              key <AC01> { type[Group1] = "FOUR_LEVEL_ALPHABETIC",
                           [ a, A, adiaeresis, Adiaeresis ] };
              key <AD09> { type[Group1] = "FOUR_LEVEL_ALPHABETIC",
                           [ o, O, odiaeresis, Odiaeresis ] };
              key <AD07> { type[Group1] = "FOUR_LEVEL_ALPHABETIC",
                           [ u, U, udiaeresis, Udiaeresis ] };
              key <AC02> { type[Group1] = "FOUR_LEVEL_SEMIALPHABETIC",
                           [ s, S, ssharp, U1E9E ] };

              include "level3(lalt_switch)"
          };
        '';
      };
    };
  };

  # libxkbcommon durchsucht fest /etc/xkb, ~/.config/xkb und ~/.xkb, danach das
  # einkompilierte (ungepatchte!) xkeyboard-config. Ohne das hier findet das
  # Layout nur, wer XKB_CONFIG_ROOT geerbt hat — Prozesse ohne die Variable
  # fallen still auf "us" zurück. Nicht existierende Suchpfade verwirft
  # libxkbcommon beim Start, deshalb muss das Verzeichnis dauerhaft da sein.
  environment.etc."xkb".source = config.services.xserver.xkb.dir;

  # NixOS setzt XKB_CONFIG_ROOT fuer extraLayouts von sich aus
  # (nixos/modules/services/x11/extra-layouts.nix) — aber nur ueber
  # environment.sessionVariables, und das erreicht nur Login-Shells und PAM.
  # Die GNOME-Sitzung haengt darunter nicht: gnome-shell laeuft als Unit des
  # systemd-Nutzermanagers, und dessen Umgebung kennt die Variable nicht.
  #
  # Folge, gemessen am laufenden System: Mutter findet das Layout us-umlaut
  # nicht und ersetzt es still durch us — die geladene Keymap hiess
  # "pc_us_de_2_inet", <AC01> hatte nur [a, A] statt der dritten Ebene mit
  # adiaeresis. Kein Fehler, keine Meldung, nur das falsche Layout.
  #
  # Dateien in environment.d liest der systemd-environment-d-generator in die
  # Umgebung des Nutzermanagers ein, und damit erbt sie auch gnome-shell.
  environment.etc."environment.d/10-xkb-config-root.conf".text = ''
    XKB_CONFIG_ROOT=${config.services.xserver.xkb.dir}
  '';

  # Display Manager
  # wayland-Option mit GNOME 50 (nixpkgs 26.11) entfernt — Wayland ist der
  # einzige unterstützte Modus, das Setzen hat keinen Effekt mehr.
  services.displayManager.gdm = {
    enable = true;
  };

  # Der Anmeldebildschirm läuft als Systemdienst und sieht
  # environment.sessionVariables nicht — ohne das hier fände Mutter im
  # Greeter das eigene Layout us-umlaut nicht und fiele auf us zurück.
  systemd.services.display-manager.environment.XKB_CONFIG_ROOT =
    config.services.xserver.xkb.dir;

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

  # Konsolen-Tastaturlayout — passt zur US-Hardware
  console.keyMap = "us";

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
    gnomeExtensions.appindicator # Tray-Icon Support
  ];

  # ==========================================
  # FONTS
  # ==========================================

  fonts.packages = with pkgs; [
    nerd-fonts.hack
  ];
}
