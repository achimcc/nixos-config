# Home Manager Konfiguration für User "achim"
# Ausgelagert aus configuration.nix für bessere Übersichtlichkeit

{ pkgs, llm-agents, ... }: # llm-agents statt nurPkgs

{
  imports = [
    ./modules/home/gnome-settings.nix
  ];

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

    # --- GNOME ERWEITERUNGEN ---
    gnomeExtensions.pano
    libgda5
    gsound

    # --- SCREENSHOT & CLIPBOARD (Wayland) ---
    grim # Screenshot-Tool
    slurp # Bereichsauswahl
    swappy # Screenshot-Annotation
    wl-clipboard # Clipboard für Wayland

    # --- NIX ENTWICKLUNG ---
    nil
    nixpkgs-fmt

    # --- TYPST ---
    typst
    tinymist
    hunspellDicts.de-de

    # --- PDF VIEWER ---
    mupdf

    # --- MEDIA PLAYER ---
    glide-media-player

    # --- EDITOREN ---
    zed-editor

    # --- RUST ENTWICKLUNG ---
    rustup # Enthält rust-analyzer (rustup component add rust-analyzer)
    gcc

    # --- KOMMUNIKATION ---
    # Wayland-Unterstützung für Signal aktivieren (sonst schwarzer Kasten)
    (symlinkJoin {
      name = "signal-desktop-wayland";
      paths = [ signal-desktop ];
      buildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/signal-desktop \
          --add-flags "--ozone-platform=wayland" \
          --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
          --add-flags "--disable-gpu-sandbox" \
          --add-flags "--use-gl=egl"
      '';
    })

    # --- AI CODING ASSISTANT ---
    # Hier nutzen wir nun den korrekten Flake-Input
    llm-agents.packages.${pkgs.system}.crush
  ];

  # --- PGP KONFIGURATION ---
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gnome3;
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
    signing = {
      key = null; # GPG wählt automatisch den Key passend zur E-Mail
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # --- VS CODIUM (Open Source VSCode ohne Microsoft Telemetrie) ---
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        vadimcn.vscode-lldb
        myriad-dreamin.tinymist
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

        # -- TYPST --
        "tinymist.serverPath" = "tinymist";
        "tinymist.exportPdf" = "onSave";

        # VSCodium Terminal
        "terminal.integrated.defaultProfile.linux" = "nushell";
        "terminal.integrated.profiles.linux" = {
          "nushell" = {
            "path" = "${pkgs.nushell}/bin/nu";
          };
        };
        "terminal.integrated.fontFamily" = "'Hack Nerd Font Mono'";

        # -- PRIVACY --
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none"; # Updates via Nix
      };
    };
  };

  # --- BROWSER (LibreWolf) ---
  programs.librewolf = {
    enable = true;
    settings = {
      "privacy.clearOnShutdown.history" = false;
      "privacy.resistFingerprinting" = true; # Manchmal nötig für Streaming/Captchas
      "privacy.clearOnShutdown.cookies" = false;
      "privacy.clearOnShutdown.sessions" = false;
      "browser.startup.page" = 3;
      "xpinstall.signatures.required" = true;
    };

    policies = {
      ExtensionSettings = {
        # KeePassXC
        "keepassxc-browser@keepassxc.org" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
        };
        # ClearURLs - entfernt Tracking-Parameter aus URLs
        "{74145f27-f039-47ce-a470-a662b129930a}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
        };
        # Multi-Account Containers
        "@testpilot-containers" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/multi-account-containers/latest.xpi";
        };
        # uBlock Origin
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };
      };
      "3rdparty" = {
        "Extensions" = {
          "uBlock0@raymondhill.net" = {
            "adminSettings" = {
              # 1. User Settings (Benutzeroberfläche)
              "userSettings" = {
                "uiTheme" = "dark"; # Dark Mode erzwingen
                "advancedUserEnabled" = true; # "Ich bin ein erfahrener Nutzer" (Wichtig für Dynamic Filtering)
              };

              # 2. Ausgewählte Filterlisten
              # WICHTIG: Die Namen müssen exakt den internen IDs von uBlock entsprechen.
              "selectedFilterLists" = [
                "user-filters" # Deine eigenen Filter
                "ublock-filters" # uBlock Base
                "ublock-badware" # Malware Protection
                "ublock-privacy" # Privacy Protection
                "ublock-unbreak" # Fixes für kaputte Seiten
                "easylist" # Ads
                "easyprivacy" # Tracking
                "urlhaus-1" # Online Malicious URL Blocklist
                "plowe-0" # Peter Lowe's Ad and tracking server list
                "DEU-0" # EasyList Germany (Wichtig für deutsche Seiten!)
                "ublock-cookies-easylist" # Cookie-Banner Blocker (EasyList Cookie)
                "adguard-generic" # AdGuard Base (Ergänzung zu EasyList)
                "ublock-cookies-adguard" # AdGuard Cookie-Banner Liste
              ];
            };
          };
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
      EDITOR = "vim";
    };
    extraConfig = ''
      $env.config.show_banner = false
    '';
  };

  # --- PDF VIEWER (Zathura mit MuPDF Backend) ---
  programs.zathura = {
    enable = true;
    options = {
      # Darstellung
      default-bg = "#1e1e2e";
      default-fg = "#cdd6f4";
      recolor = true;
      recolor-lightcolor = "#1e1e2e";
      recolor-darkcolor = "#cdd6f4";
      recolor-keephue = true;

      # Verhalten
      selection-clipboard = "clipboard";
      adjust-open = "best-fit";
      scroll-page-aware = true;
      smooth-scroll = true;
      scroll-step = 100;

      # Statusbar
      statusbar-home-tilde = true;
      window-title-home-tilde = true;
    };
    mappings = {
      # Vim-ähnliche Navigation
      "<C-d>" = "scroll half-down";
      "<C-u>" = "scroll half-up";
      D = "toggle_page_mode";
      r = "reload";
      R = "rotate";
      i = "recolor";
    };
  };


  # AUTORUN: ProtonVPN beim Login starten
  xdg.configFile."autostart/protonvpn-autostart.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=ProtonVPN AutoStart
    Comment=Startet ProtonVPN beim Systemstart
    Exec=protonvpn-app
    Icon=proton-vpn-logo
    Terminal=false
    Categories=Network;Security;
    X-GNOME-Autostart-enabled=true
  '';
}
