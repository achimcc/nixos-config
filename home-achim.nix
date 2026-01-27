# Home Manager Konfiguration für User "achim"
# Ausgelagert aus configuration.nix für bessere Übersichtlichkeit

{ config, pkgs, pkgs-unstable, llm-agents, ... }:

{
  imports = [
    ./modules/home/gnome-settings.nix
    ./modules/home/neovim.nix
  ];

  home.stateVersion = "24.11";

  # ==========================================
  # FLATPAK - Signal Desktop (deklarativ)
  # ==========================================

  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    packages = [
      "org.signal.Signal"
      "org.jdownloader.JDownloader"
    ];
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # Signal Autostart (Flatpak)
  xdg.configFile."autostart/org.signal.Signal.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Signal
    Exec=flatpak run org.signal.Signal --start-in-tray
    X-GNOME-Autostart-enabled=true
  '';

  # WICHTIG FÜR RUST:
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  # User-spezifische Pakete
  home.packages = with pkgs; [

    # --- VPN & NETZWERK SICHERHEIT ---
    protonvpn-gui # GUI zusätzlich zur CLI

    # --- SICHERHEIT & TOOLS ---
    bitwarden-desktop # Passwort-Manager Desktop-App (für Browser-Biometrics)
    kdePackages.kleopatra
    usbguard-notifier # Desktop-Benachrichtigungen für blockierte USB-Geräte

    # --- GNOME ERWEITERUNGEN ---
    gnomeExtensions.pano
    libgda5
    gsound

    # --- SYSTEM MONITORING ---
    mission-center

    # --- SYNCTHING ---
    # syncthingtray # Temporär deaktiviert (Cache-Problem mit acl-2.3.2 Hash-Mismatch)

    # --- RSS READER ---
    newsflash # GTK RSS-Reader (mit Miniflux-Sync)

    # --- FINANZEN ---
    portfolio # Portfolio Performance - Wertpapierdepot-Verwaltung

    # --- SCREENSHOT & CLIPBOARD (Wayland) ---
    grim # Screenshot-Tool
    slurp # Bereichsauswahl
    swappy # Screenshot-Annotation
    wl-clipboard # Clipboard für Wayland

    # --- GIT TOOLS ---
    gitui # Terminal UI für Git
    delta # Syntax-Highlighting für Git Diffs

    # --- MODERN UNIX CLI TOOLS ---
    ripgrep # rg - schnelle Suche, ersetzt grep
    bat # Syntax-Highlighting cat
    eza # Modernes ls mit Icons und Git-Status
    fd # Schnelles find mit intuitiver Syntax
    bottom # btm - grafischer Prozess-Monitor
    xh # HTTP-Client mit JSON-Formatting
    dust # Visualisierte Festplattenbelegung

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
    # logseq - via Firejail in modules/network.nix

    # --- RUST ENTWICKLUNG ---
    # Deklarative Rust-Toolchain aus unstable (Rust 1.92+)
    pkgs-unstable.cargo
    pkgs-unstable.rustc
    pkgs-unstable.rust-analyzer
    pkgs-unstable.clippy
    pkgs-unstable.rustfmt
    cargo-nextest # Next-generation test runner
    cargo-depgraph # Dependency graph visualization
    graphviz # Für cargo-depgraph Visualisierung
    gcc

    # --- KOMMUNIKATION ---
    # Signal Desktop wird über Firejail in modules/network.nix installiert

    # --- NODE.JS ---
    nodejs_22 # Enthält npm für globale Pakete

    # ---- youtube
    freetube

    # --- DOWNLOAD MANAGER ---
    motrix

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
    aider-chat # AI pair programming
    llm-agents.packages.${pkgs.system}.crush
    # claude-code via npm installieren: npm install -g @anthropic-ai/claude-code
    
    # --- NETWORK SIMULATOR ---
    shadow-simulator # Discrete-event network simulator für verteilte Systeme
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
      # Delta als Pager für bessere Diffs
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        light = false;
        line-numbers = true;
      };
      merge.conflictStyle = "diff3";
      diff.colorMoved = "default";
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
        serayuzgur.crates # Zeigt Crate-Versionen in Cargo.toml
      ] ++ [
        # TangleGuard - Dependency Graph Visualisierung
        (pkgs.vscode-utils.extensionFromVscodeMarketplace {
          publisher = "ArchwiseSolutionsUG";
          name = "tangleguard";
          version = "0.0.8";
          sha256 = "09cd8ka4nrys1wcg09c20i65mxxl6mk6li8rxap60w8f2rn6gixq";
        })
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
  # LibreWolf wird über Firejail in modules/network.nix installiert und gesandboxt.
  # package = null verhindert doppelte Installation, wendet nur Settings/Extensions an.
  programs.librewolf = {
    enable = true;
    package = null; # Paket kommt via Firejail-Wrapper aus network.nix
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

  # Browser-Integration für Goldwarden wird via `goldwarden setup browserbiometrics` konfiguriert
  # Das erstellt die native-messaging-hosts Dateien im Profil-Verzeichnis

  # Librewolf Extensions (da package=null werden policies nicht automatisch angewendet)
  # Diese Datei wird von Librewolf beim Start gelesen
  home.file.".librewolf/distribution/policies.json".text = builtins.toJSON {
    policies = {
      ExtensionSettings = {
        # Bitwarden (mit Goldwarden für Biometrics)
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
        };
      };
    };
  };

  # --- RUST TOOLING KONFIGURATION ---

  # cargo-nextest Konfiguration
  home.file.".config/nextest/config.toml".text = ''
    # cargo-nextest Konfiguration
    # Dokumentation: https://nexte.st/book/configuration.html

    [profile.default]
    # Anzahl paralleler Test-Jobs (Standard: logische CPU-Kerne)
    test-threads = "num-cpus"

    # Fortschrittsanzeige
    status-level = "pass"
    final-status-level = "fail"

    # Test-Ausgabe Einstellungen
    failure-output = "immediate"
    success-output = "never"

    # Retry-Strategie für flaky Tests
    retries = 0

    [profile.ci]
    # Strengeres Profil für CI/CD
    retries = 2
    status-level = "all"
    failure-output = "immediate"
    success-output = "final"
  '';

  # --- RSS READER KONFIGURATION ---
  # Newsflash Miniflux-Zugangsdaten werden manuell in der GUI konfiguriert:
  # Settings → Accounts → Add Account → Miniflux
  # URL: https://rusty-vault.de/miniflux
  # Username: admin (aus sops: miniflux/username)
  # Password: (aus sops: miniflux/password)

  # --- SHELL CONFIGURATION ---

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.nushell = {
    enable = true;
    shellAliases = {
      # Modern Unix Aliase
      ls = "eza --icons";
      ll = "eza -l --icons --git";
      la = "eza -la --icons --git";
      lt = "eza --tree --icons";
      cat = "bat";
      grep = "rg";
      find = "fd";
      top = "btm";
      du = "dust";
      # Git
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      # Sonstiges
      obb = "openbb"; # FHS-wrapped, installiert automatisch beim ersten Start
      nrs = "sudo nixos-rebuild switch --flake /home/achim/nixos-config#achim-laptop";
      charge = "sudo tlp fullcharge";
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

        # Eigener Relay-Server auf VPS (bevorzugt vor öffentlichen Relays)
        relayServers = [
          "relay://rusty-vault.de:22067"
        ];
      };

      # GUI nur lokal erreichbar
      gui = {
        theme = "dark";
        # Zugriff nur von localhost
        address = "127.0.0.1:8384";
      };

      # Deklarative Geräte-Konfiguration
      # Hinweis: Device IDs sind öffentliche Identifikatoren (nicht geheim)
      devices = {
        "handy" = {
          id = "5E6BMTG-QDGJW2C-MKKX4J4-7I6ZJWY-IM6KISC-YYGAMZZ-PIEENVJ-XMOQQAM";
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
