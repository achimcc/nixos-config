# Home Manager Konfiguration für User "achim"
# Ausgelagert aus configuration.nix für bessere Übersichtlichkeit

{ config, pkgs, llm-agents, ... }: # llm-agents statt nurPkgs

{
  imports = [
    ./modules/home/gnome-settings.nix
    ./modules/home/neovim.nix
  ];

  home.stateVersion = "24.11";

  # WICHTIG FÜR RUST:
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  # User-spezifische Pakete
  home.packages = with pkgs; [

    # --- VPN & NETZWERK SICHERHEIT ---
    protonvpn-gui # GUI zusätzlich zur CLI

    # --- SICHERHEIT & TOOLS ---
    keepassxc
    kdePackages.kleopatra

    # --- GNOME ERWEITERUNGEN ---
    gnomeExtensions.pano
    libgda5
    gsound

    # --- SYSTEM MONITORING ---
    mission-center

    # --- FINANZEN ---
    portfolio # Portfolio Performance - Wertpapierdepot-Verwaltung

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
    apostrophe # Markdown-Editor für GNOME

    # --- RUST ENTWICKLUNG ---
    rustup # Enthält rust-analyzer (rustup component add rust-analyzer)
    gcc

    # --- KOMMUNIKATION ---
    # Signal Desktop wird über Firejail in modules/network.nix installiert

    # --- NODE.JS ---
    nodejs_22 # Enthält npm für globale Pakete

    # ---- youtube
    freetube

    # --- OPENBB (Investment Research Platform) ---
    # FHS-kompatible Umgebung für OpenBB (pip-basiert)
    # Python 3.11 für Kompatibilität mit älteren OpenBB-Versionen
    (pkgs.buildFHSEnv {
      name = "openbb";
      targetPkgs = pkgs: with pkgs; [
        (python311.withPackages (ps: with ps; [
          pip
          virtualenv
          numpy
          pandas
          scipy
          matplotlib
          requests
          aiohttp
          pydantic
          python-dotenv
        ]))
        gcc
        zlib
        openssl
        libffi
      ];
      runScript = pkgs.writeShellScript "openbb-wrapper" ''
        VENV_DIR="$HOME/.local/share/openbb-venv"
        if [ ! -d "$VENV_DIR" ]; then
          echo "Erstelle OpenBB venv..."
          python -m venv "$VENV_DIR"
          "$VENV_DIR/bin/pip" install --upgrade pip
          # Stabile Version ohne commodity-Bug (benötigt Python <3.12)
          "$VENV_DIR/bin/pip" install "openbb==4.2.0" "openbb-cli==1.0.0" openbb-charting
        fi
        exec "$VENV_DIR/bin/openbb" "$@"
      '';
    })

    # --- AI CODING ASSISTANT ---
    # Hier nutzen wir nun den korrekten Flake-Input
    llm-agents.packages.${pkgs.system}.crush
    # claude-code via npm installieren: npm install -g @anthropic-ai/claude-code
  ];

  # --- PGP KONFIGURATION ---
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gnome3;
    enableSshSupport = true;
  };

  # --- EMAIL ACCOUNT KONFIGURATION ---
  # Definiert den Posteo Account für Thunderbird und andere Mail-Tools
  accounts.email.accounts.posteo = {
    primary = true;
    address = "achim.schneider@posteo.de";
    userName = "achim.schneider@posteo.de";
    realName = "Achim Schneider";

    # IMAP Konfiguration (Empfang)
    imap = {
      host = "posteo.de";
      port = 993;
      tls.enable = true;
    };

    # SMTP Konfiguration (Versand)
    smtp = {
      host = "posteo.de";
      port = 465;
      tls.enable = true;
    };

    # Thunderbird Integration
    thunderbird = {
      enable = true;
      profiles = [ "achim" ];
    };
  };

  # --- POSTEO PASSWORT IN GNOME KEYRING ---
  # Lädt das Posteo-Passwort aus sops in den GNOME Keyring beim Login
  # Thunderbird greift automatisch darauf zu
  systemd.user.services.posteo-keyring-sync = {
    Unit = {
      Description = "Sync Posteo password from sops to GNOME Keyring";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "posteo-keyring-sync" ''
        # Warte bis Keyring bereit ist
        sleep 3
        
        # Passwort aus sops lesen
        if [ -f /run/secrets/email/posteo ]; then
          PASSWORD=$(cat /run/secrets/email/posteo)
          
          # In GNOME Keyring speichern (Format das Thunderbird erwartet)
          # IMAP Passwort
          echo -n "$PASSWORD" | ${pkgs.libsecret}/bin/secret-tool store --label="Posteo IMAP" \
            protocol imap \
            server posteo.de \
            user "achim.schneider@posteo.de"
          
          # SMTP Passwort
          echo -n "$PASSWORD" | ${pkgs.libsecret}/bin/secret-tool store --label="Posteo SMTP" \
            protocol smtp \
            server posteo.de \
            user "achim.schneider@posteo.de"
        fi
      '';
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
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
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      # SSH-Signierung statt GPG
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
    };
  };

  # Allowed Signers für SSH-Commit-Verifizierung
  home.file.".ssh/allowed_signers".text = ''
    achim.schneider@posteo.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxoCdoA7621jMhv0wX3tx66NEZMv9tp8xdE76sEfjBI
  '';

  # --- GITHUB CLI ---
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      editor = "nvim";
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
  # HINWEIS: LibreWolf wird über Firejail in modules/network.nix installiert und gesandboxt.
  # Diese Konfiguration wendet nur Settings und Extensions an.
  programs.librewolf = {
    enable = true;
    package = pkgs.librewolf; # Explizit setzen für Konfiguration (Firejail-Wrapper hat Priorität)
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
        # uBlock Origin - bereits in LibreWolf enthalten, nur Konfiguration via 3rdparty
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
      obb = "openbb"; # FHS-wrapped, installiert automatisch beim ersten Start
    };
    environmentVariables = {
      EDITOR = "vim";
      NPM_CONFIG_PREFIX = "~/.npm-global";
    };
    extraConfig = ''
      $env.config.show_banner = false
      $env.PATH = ($env.PATH | prepend $"($env.HOME)/.npm-global/bin")

      # Anthropic API Key aus sops Secret laden (für avante.nvim, crush, etc.)
      if ("/run/secrets/anthropic-api-key" | path exists) {
        $env.ANTHROPIC_API_KEY = (open /run/secrets/anthropic-api-key | str trim)
      }

      # GitHub Token aus sops Secret laden (für gh CLI, octo.nvim)
      if ("/run/secrets/github-token" | path exists) {
        $env.GH_TOKEN = (open /run/secrets/github-token | str trim)
      }
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


  # ProtonVPN wird via systemd beim Boot gestartet (siehe modules/protonvpn.nix)
  # GUI läuft zusätzlich und zeigt die bestehende Verbindung an

  # ==========================================
  # SYNCTHING - Sichere Dateisynchronisation
  # ==========================================
  services.syncthing = {
    enable = true;

    # Sicherheitseinstellungen
    settings = {
      options = {
        # Keine anonyme Nutzungsstatistik
        urAccepted = -1;

        # Relaying aktivieren (für Verbindungen hinter NAT/Firewall)
        relaysEnabled = true;

        # Globale Discovery aktivieren (findet Geräte über Internet)
        globalAnnounceEnabled = true;

        # Lokale Discovery aktivieren (findet Geräte im selben Netzwerk)
        localAnnounceEnabled = true;

        # NAT Traversal aktivieren (für Verbindungen hinter NAT)
        natEnabled = true;

        # Automatische Upgrades deaktivieren (Updates via Nix)
        autoUpgradeIntervalH = 0;
      };

      # GUI nur lokal erreichbar
      gui = {
        theme = "dark";
        # Zugriff nur von localhost
        address = "127.0.0.1:8384";
      };

      # Deklarative Geräte-Konfiguration
      # Geräte-IDs werden aus SOPS Secrets geladen
      devices = {
        "handy" = {
          # Geräte-ID wird unten via sops.templates gesetzt
          id = "5E6BMTG-QDGJW2C-MKKX4J4-7I6ZJWY-IM6KISC-YYGAMZZ-PIEENVJ-XMOQQAM";
          # Keine Auto-Accept für eingehende Ordner (muss manuell bestätigt werden)
          autoAcceptFolders = false;
        };
        "handy-google" = {
          id = "ZPTESBS-PP56L6O-BHJ4SFU-DQZHE4L-RAQ6UYA-PYHQH74-FWLSNC3-DOKGHAW";
          autoAcceptFolders = false;
        };
      };
    };
  };
}
