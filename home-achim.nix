# Home Manager Konfiguration für User "achim"
# Ausgelagert aus configuration.nix für bessere Übersichtlichkeit

{ config, pkgs, pkgs-unstable, llm-agents, rcu, ... }:

let
  easyeffects-presets = pkgs.stdenv.mkDerivation {
    name = "easyeffects-presets-jackhack96";
    src = pkgs.fetchFromGitHub {
      owner = "JackHack96";
      repo = "EasyEffects-Presets";
      rev = "master";
      hash = "sha256-or5kH/vTwz7IO0Vz7W4zxK2ZcbL/P3sO9p5+EdcC2DA=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/output $out/irs
      cp *.json $out/output/
      cp irs/* $out/irs/ 2>/dev/null || true
      # IRS-Pfade in Presets anpassen
      substituteInPlace $out/output/*.json \
        --replace-quiet "PRESETS_DIRECTORY" "$out"
    '';
  };
in
{
  imports = [
    ./modules/home/gnome-settings.nix
    ./modules/home/neovim.nix
    ./modules/home/sway.nix
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
      "org.jdownloader.JDownloader"
      "info.portfolio_performance.PortfolioPerformance"
      "de.schmidhuberj.Flare"
      "org.nickvision.money" # Denaro - Persönliche Finanzverwaltung
    ];
    overrides = {
      "de.schmidhuberj.Flare" = {
        "Session Bus Policy"."org.freedesktop.secrets" = "talk";
        # CA-Zertifikate für SSL-Verbindungen (Signal-Server)
        # /etc/ssl/certs ist standardmäßig im Flatpak-Sandbox zugänglich
        "Environment" = {
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        };
      };
    };
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # PATH-Erweiterungen (haben Priorität vor system/user defaults)
  home.sessionPath = [
    "$HOME/.local/bin"  # Für Wrapper-Scripts (z.B. Firejail-Wrapper für codium)
    "$HOME/.cargo/bin"  # Rust/Cargo binaries
  ];

  # SSH Agent Socket für FIDO2-Schlüssel
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";

    # Intel i915 Vulkan GPU Hang Workaround (2026-02-08, reaktiviert 2026-02-09)
    # Erzwingt OpenGL-Renderer statt Vulkan für GTK4/GNOME Apps
    # Verhindert GPU HANGs in Nautilus, Apostrophe, Loupe (Meteor Lake GPU Bug)
    # WICHTIG: Auch ohne GuC bleibt Vulkan instabil → OpenGL ist sicherer
    GSK_RENDERER = "gl";
  };

  # User-spezifische Pakete
  home.packages = with pkgs; [

    # --- VPN & NETZWERK SICHERHEIT ---
    protonvpn-gui # GUI zusätzlich zur CLI

    # --- SICHERHEIT & TOOLS ---
    bitwarden-desktop # Passwort-Manager Desktop-App (für Browser-Biometrics)
    kdePackages.kleopatra
    usbguard-notifier # Desktop-Benachrichtigungen für blockierte USB-Geräte
    raider # Sicheres Löschen von Dateien (GNOME/libadwaita)

    # --- NITROKEY 3C NFC ---
    nitrokey-app2 # GUI-Verwaltung (FIDO2 PIN, Firmware-Update, OpenPGP)
    pkgs-unstable.pynitrokey # CLI-Tool: nitropy fido2/openpgp (Firmware-Updates, FIDO2-Verwaltung)
    libfido2 # CLI: fido2-token (Low-Level FIDO2-Verwaltung)

    # --- GNOME ERWEITERUNGEN ---
    gnomeExtensions.pano
    libgda5
    gsound

    # --- SYSTEM MONITORING ---
    mission-center
    baobab # GNOME Festplattenbelegung (grafisch)
    czkawka-full # Duplikate-Finder mit GUI (ähnliche Bilder, leere Ordner etc.)

    # --- AUDIO ---
    helvum # GTK Patchbay für PipeWire
    easyeffects # Equalizer & Audio-Effekte für PipeWire
    lsp-plugins # Audio-Plugins (Abhängigkeit für EasyEffects-Presets)

    # --- RADIO ---
    shortwave # Internet-Radio (GNOME/libadwaita)

    # --- SYNCTHING ---
    # syncthingtray # Temporär deaktiviert (Cache-Problem mit acl-2.3.2 Hash-Mismatch)

    # --- DOWNLOADS & TORRENTS ---
    parabolic # Video/Audio-Downloader (yt-dlp Frontend, GNOME/libadwaita)
    fragments # BitTorrent-Client (GNOME/libadwaita)

    # --- RSS READER ---
    newsflash # GTK RSS-Reader (mit Miniflux-Sync)

    # --- FINANZEN ---
    # portfolio - via Flatpak (siehe services.flatpak.packages)

    # --- SCREENSHOT & CLIPBOARD (Wayland) ---
    grim # Screenshot-Tool
    slurp # Bereichsauswahl
    swappy # Screenshot-Annotation
    wl-clipboard # Clipboard für Wayland
    textsnatcher # OCR - Text aus Bildern kopieren

    # --- GIT TOOLS ---
    gitui # Terminal UI für Git
    delta # Syntax-Highlighting für Git Diffs
    glab # GitLab CLI

    # --- MODERN UNIX CLI TOOLS ---
    ripgrep # rg - schnelle Suche, ersetzt grep
    bat # Syntax-Highlighting cat
    eza # Modernes ls mit Icons und Git-Status
    lsd # LSDeluxe - Alternative zu eza/ls mit Icons
    fd # Schnelles find mit intuitiver Syntax
    bottom # btm - grafischer Prozess-Monitor
    duf # Disk Usage/Free - Schöneres df
    dust # Visualisierte Festplattenbelegung
    xh # HTTP-Client mit JSON-Formatting
    yazi # Terminal-Dateimanager mit Vorschau
    tealdeer # tldr - Vereinfachte Man-Pages
    tokei # Code-Statistiken (Lines of Code)
    doggo # Moderner DNS-Client (dig-Ersatz)
    fx # JSON Viewer/Explorer (interaktiv)
    gum # Fancy Shell Script UI Components
    viddy # Moderner watch-Befehl mit Diffs
    # resterm # REST client - nicht in nixpkgs verfügbar

    # --- ENTWICKLER TOOLS ---
    wildcard # Regex-Tester (GNOME/libadwaita)
    elastic # Spring-Animationen designen (GNOME/libadwaita)

    # --- NIX ENTWICKLUNG ---
    nil
    nixpkgs-fmt

    # --- TYPST ---
    typst
    tinymist
    hunspellDicts.de-de

    # --- MARKDOWN TO PDF ---
    pandoc # Universal Dokumenten-Konverter (Markdown → PDF, DOCX, HTML, etc.)
    texliveSmall # LaTeX für Pandoc PDF-Generierung (kompakte Distribution)

    # --- PDF VIEWER & E-BOOKS ---
    evince # GNOME Document Viewer (via Firejail in modules/network.nix)
    foliate # E-Book-Reader (GNOME/libadwaita)
    calibre # E-Book-Management & -Konvertierung

    # --- MEDIA PLAYER ---
    vlc # VLC Media Player (exzellentes SW-Decoding, wichtig mit nomodeset)
    celluloid # GTK-Frontend für mpv
    amberol # GNOME Musik-Player für lokale Dateien

    # --- TERMINAL ---
    blackbox-terminal
    wezterm

    # --- NOTIZEN & ZEICHNEN ---
    rnote # Handschriftliche Notizen und Skizzen (GTK/libadwaita)

    # --- EDITOREN ---
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

    # --- FLUTTER/DART ENTWICKLUNG ---
    flutter

    # --- KOMMUNIKATION ---
    # Signal Desktop + Flare via Flatpak (siehe services.flatpak.packages)

    # --- NODE.JS ---
    nodejs_22 # Enthält npm für globale Pakete

    # --- FHS COMPATIBILITY ---
    steam-run # FHS-Umgebung für nicht-NixOS Binaries

    # ---- youtube
    freetube

    # --- DOWNLOAD MANAGER ---
    motrix
    fragments # GNOME BitTorrent-Client

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
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.crush
    # claude-code via npm installieren: npm install -g @anthropic-ai/claude-code

    # --- RESUME / CV ---
    resumed # JSON Resume builder (lightweight alternative to resume-cli)

    # --- NETWORK SIMULATOR ---
    shadow-simulator # Discrete-event network simulator für verteilte Systeme

    # --- REMARKABLE TABLET ---
    rcu.packages.${pkgs.stdenv.hostPlatform.system}.default # RCU - reMarkable Connection Utility
  ];

  # --- PGP KONFIGURATION ---
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    # Wrapper für pinentry-gnome3 mit D-Bus Umgebung
    pinentry.package = pkgs.writeShellScriptBin "pinentry" ''
      export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
      exec ${pkgs.pinentry-gnome3}/bin/pinentry "$@"
    '';
    enableSshSupport = false; # Deaktiviert - gpg-agent unterstützt FIDO2-Schlüssel nicht vollständig
    # Cache GPG-Passwort für 8 Stunden (verhindert ständige Passwort-Prompts)
    defaultCacheTtl = 28800;  # 8 Stunden in Sekunden
    maxCacheTtl = 28800;      # Maximale Cache-Zeit
  };

  # GPG-Agent Service: D-Bus Umgebung für Pinentry setzen
  systemd.user.services.gpg-agent.Service.Environment = [
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
  ];

  # SSH-Agent als systemd user service (für FIDO2/Nitrokey-Unterstützung)
  systemd.user.services.ssh-agent = {
    Unit = {
      Description = "SSH Agent (for FIDO2 keys)";
    };
    Service = {
      Type = "simple";
      Environment = "SSH_AUTH_SOCK=%t/ssh-agent.socket";
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a $SSH_AUTH_SOCK";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # GNOME Keyring SSH-Agent deaktivieren (Konflikt mit ssh-agent service)
  xdg.configFile."autostart/gnome-keyring-ssh.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=GNOME Keyring: SSH Agent
    Hidden=true
  '';

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

  # --- POSTEO KALENDER (GNOME Online Accounts / CalDAV) ---
  # Deklarative Konfiguration des Posteo CalDAV-Accounts für GNOME Kalender
  xdg.configFile."goa-1.0/accounts.conf".text = ''
    [Account account_posteo_caldav_0]
    Provider=webdav
    Identity=achim.schneider@posteo.de
    PresentationIdentity=achim.schneider@posteo.de
    Uri=https://posteo.de:8443
    CalendarEnabled=true
    CalDavUri=https://posteo.de:8443/calendars/achim.schneider@posteo.de/default/
    ContactsEnabled=false
    FilesEnabled=false
    AcceptSslErrors=false
  '';

  # --- POSTEO PASSWORT IN GNOME KEYRING ---
  # Lädt das Posteo-Passwort aus sops in den GNOME Keyring beim Login
  # Thunderbird und GNOME Online Accounts greifen automatisch darauf zu
  systemd.user.services.posteo-keyring-sync = {
    Unit = {
      Description = "Sync Posteo password from sops to GNOME Keyring";
      # CRITICAL: Warte bis GNOME vollständig geladen ist (nicht nur Keyring-Service!)
      # Verhindert Race Condition die zu korrupten Keyring-Dateien führt
      # Startet NACH gnome-shell (Desktop vollständig geladen)
      After = [ "graphical-session.target" "gnome-keyring.service" "gnome-shell-wayland.service" ];
      PartOf = [ "graphical-session.target" ];
      # Zusätzliche Absicherung: Starte erst wenn Session wirklich bereit ist
      Wants = [ "gnome-shell-wayland.service" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Delay vor dem Start (gibt GNOME Zeit zum Starten)
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = pkgs.writeShellScript "posteo-keyring-sync" ''
        set -e  # Bei Fehler abbrechen

        # Robuste Wartezeit bis Keyring wirklich bereit ist (max 60s statt 30s)
        # Verhindert Schreiben in Keyring während er noch lädt (→ Korruption)
        echo "Warte auf GNOME Keyring..."
        for i in {1..60}; do
          # Prüfe ob Keyring antwortet (lookup gibt Exit Code 1 wenn nicht bereit)
          # Verwende lookup statt search, da lookup einen klaren Exit Code zurückgibt
          if ${pkgs.libsecret}/bin/secret-tool lookup nonexistent test 2>/dev/null; then
            # Keyring antwortet (auch wenn nicht gefunden)
            :
          fi
          # Wenn Exit Code ist (0 oder 1, nicht Timeout/Error), dann ist Keyring bereit
          if [ $? -lt 2 ]; then
            # Zusätzliche Sicherheit: Warte weitere 3 Sekunden
            sleep 3
            echo "GNOME Keyring ist bereit (nach $i Sekunden)"
            break
          fi
          if [ $i -eq 60 ]; then
            echo "FEHLER: GNOME Keyring nicht bereit nach 60 Sekunden!"
            exit 1
          fi
          sleep 1
        done

        # Passwort aus sops lesen
        if [ ! -f /run/secrets/email/posteo ]; then
          echo "FEHLER: /run/secrets/email/posteo nicht gefunden!"
          exit 1
        fi

        PASSWORD=$(cat /run/secrets/email/posteo)

        # In GNOME Keyring speichern (Format das Thunderbird erwartet)
        echo "Schreibe Posteo-Credentials in Keyring..."

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

        # GNOME Online Accounts (CalDAV für GNOME Kalender)
        # GVariant-Format: {'password': <'...'> }
        printf "{'password': <'%s'>}" "$PASSWORD" | \
          ${pkgs.libsecret}/bin/secret-tool store \
            --label="GOA webdav credentials for identity account_posteo_caldav_0" \
            xdg:schema org.gnome.OnlineAccounts \
            goa-identity "webdav:gen0:account_posteo_caldav_0"

        echo "Posteo-Credentials erfolgreich gespeichert!"
      '';
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # --- GNOME KEYRING BACKUP ---
  # Sichert den GNOME Keyring täglich, um Datenverlust bei Korruption zu verhindern
  # Hält die letzten 7 Backups
  systemd.user.services.gnome-keyring-backup = {
    Unit = {
      Description = "Backup GNOME Keyring";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gnome-keyring-backup" ''
        set -e

        BACKUP_DIR="$HOME/.local/share/keyrings/backups"
        KEYRING_DIR="$HOME/.local/share/keyrings"

        # Backup-Verzeichnis erstellen
        mkdir -p "$BACKUP_DIR"

        # Timestamp für Backup
        TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)

        # Alle Keyring-Dateien sichern
        echo "Erstelle Keyring-Backup: $TIMESTAMP"
        ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/keyring-backup-$TIMESTAMP.tar.gz" \
          -C "$KEYRING_DIR" \
          --exclude="backups" \
          . 2>/dev/null || true

        # Alte Backups löschen (behalte nur die letzten 7)
        cd "$BACKUP_DIR"
        ls -t keyring-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

        echo "Backup abgeschlossen. $(ls -1 keyring-backup-*.tar.gz 2>/dev/null | wc -l) Backups vorhanden."
      '';
    };
  };

  # Timer für tägliches Keyring-Backup
  systemd.user.timers.gnome-keyring-backup = {
    Unit = {
      Description = "Daily GNOME Keyring Backup";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;  # Führe aus wenn Zeit verpasst wurde (z.B. Laptop war aus)
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # --- GPG PUBLIC KEY EXPORT FÜR THUNDERBIRD ---
  # Exportiert den öffentlichen GPG-Schlüssel beim Login für Thunderbird-Import
  systemd.user.services.export-gpg-pubkey = {
    Unit = {
      Description = "Export GPG public key for Thunderbird";
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "export-gpg-key" ''
        mkdir -p ~/.config/thunderbird-gpg
        ${pkgs.gnupg}/bin/gpg --armor --export achim.schneider@posteo.de \
          > ~/.config/thunderbird-gpg/gpg-public-key.asc
      '';
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # --- EMAIL CLIENT (Thunderbird - Hardened) ---
  # WICHTIG: Thunderbird wird über programs.firejail.wrappedBinaries installiert (modules/network.nix)
  # Deaktiviere automatische Installation hier, um Firejail-Wrapper nicht zu überschreiben
  programs.thunderbird = {
    enable = false;
    # Profil-Einstellungen müssen manuell in about:config gesetzt werden:
    # - privacy.donottrackheader.enabled = true
    # - mailnews.message_display.disable_remote_image = true
    # - datareporting.healthreport.uploadEnabled = false
    # - datareporting.policy.dataSubmissionEnabled = false
    # - toolkit.telemetry.enabled = false
    # - javascript.enabled = false
    # - mailnews.display.html_as = 3 (Plain Text)
  };

  # Thunderbird user.js - Deklarative Konfiguration für externes GnuPG
  # Verwendet das tatsächliche Thunderbird-Profil (urcekwf0.default)
  home.file.".thunderbird/urcekwf0.default/user.js".text = ''
    // Externes GnuPG aktivieren (für Nitrokey-Unterstützung)
    user_pref("mail.openpgp.allow_external_gnupg", true);

    // GPG-Binary explizit setzen (korrekter Pfad für Home Manager)
    user_pref("mail.openpgp.gnupg_path", "${pkgs.gnupg}/bin/gpg");

    // Öffentliche Schlüssel aus GnuPG-Keyring importieren
    user_pref("mail.openpgp.fetch_pubkeys_from_gnupg", true);
  '';

  # --- SSH ---
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      # SSH-Keys automatisch zum Agent hinzufügen beim ersten Nutzen
      "*" = {
        addKeysToAgent = "yes";
      };
      "github.com" = {
        identityFile = "~/.ssh/id_ed25519_sk";
        identitiesOnly = true;
      };
      "gitlab.com" = {
        hostname = "altssh.gitlab.com";
        port = 443;
        identityFile = "~/.ssh/id_ed25519_sk";
        identitiesOnly = true;
      };
      "rusty-vault.de" = {
        identityFile = "~/.ssh/hetzner-vps";
        identitiesOnly = true;
      };
    };
  };

  # --- GIT ---
  programs.git = {
    enable = true;
    signing = {
      key = "~/.ssh/id_ed25519_sk.pub";
      signByDefault = true;
    };
    settings = {
      user.name = "Achim Schneider";
      user.email = "achim.schneider@posteo.de";
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
    achim.schneider@posteo.de sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIJ/Bouatb6CsPRo6gbqTjZUBcZuBNlXu8LHh0cHnKyamAAAABHNzaDo= achim.schneider@posteo.de
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
  # WICHTIG: VSCodium läuft via Bubblewrap-Wrapper in ~/.local/bin/codium
  # Der Wrapper isoliert VSCodium vom System und deaktiviert Electron-Sandbox
  programs.vscode = {
    enable = true;
    package = pkgs-unstable.vscodium;

    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        vadimcn.vscode-lldb
        myriad-dreamin.tinymist
        serayuzgur.crates # Zeigt Crate-Versionen in Cargo.toml
        mkhl.direnv
        usernamehw.errorlens
        continue.continue
        yzhang.markdown-all-in-one
        davidanson.vscode-markdownlint
        tomoki1207.pdf
        saoudrizwan.claude-dev # Cline
      ] ++ [
        # TangleGuard - Dependency Graph Visualisierung
        # Binary wird mit autoPatchelfHook gepatcht statt systemweitem nix-ld
        ((pkgs.vscode-utils.extensionFromVscodeMarketplace {
          publisher = "ArchwiseSolutionsUG";
          name = "tangleguard";
          version = "0.0.8";
          sha256 = "09cd8ka4nrys1wcg09c20i65mxxl6mk6li8rxap60w8f2rn6gixq";
        }).overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.autoPatchelfHook ];
          buildInputs = (old.buildInputs or []) ++ [ pkgs.stdenv.cc.cc.lib ];
        }))
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
        "files.trimTrailingWhitespace" = true;

        # -- RUST --
        "rust-analyzer.check.command" = "clippy";
        "rust-analyzer.server.path" = "rust-analyzer";
        "lldb.executable" = "lldb";

        # -- TYPST --
        "tinymist.serverPath" = "tinymist";
        "tinymist.exportPdf" = "onSave";

        # VSCodium Terminal
        "terminal.integrated.defaultProfile.linux" = "bash";
        "terminal.integrated.profiles.linux" = {
          "bash" = {
            "path" = "bash";
          };
          "nushell" = {
            "path" = "nu";
          };
        };
        "terminal.integrated.fontFamily" = "'Hack Nerd Font Mono'";

        # Externer Terminal: Black Box
        # WICHTIG: Integriertes Terminal funktioniert nicht (hardened Kernel + Electron PTY Issue)
        # Nutze externes Terminal stattdessen
        "terminal.external.linuxExec" = "${pkgs.blackbox-terminal}/bin/blackbox";

        # -- PRIVACY --
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none"; # Updates via Nix

        # -- ELECTRON SANDBOX --
        # Deaktiviert für hardened Kernel Kompatibilität
        # "native" = GNOME zeichnet Fensterbuttons (verhindert Duplikate)
        "window.titleBarStyle" = "native";
      };

      # Electron-Sandbox deaktivieren (für PTY/Terminal auf hardened Kernel)
      userSettings = {
        "terminal.integrated.inheritEnv" = true;
      };

      # Electron-Flags für VSCodium
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;
    };
  };

  # VSCodium Desktop-Datei überschreiben, um Bubblewrap-Wrapper zu verwenden
  xdg.desktopEntries.codium = {
    name = "VSCodium";
    genericName = "Text Editor";
    comment = "Code Editing. Redefined. (Sandboxed with Bubblewrap)";
    exec = "/home/achim/.local/bin/codium %F";
    icon = "vscodium";
    terminal = false;
    type = "Application";
    startupNotify = true;
    categories = [ "Utility" "TextEditor" "Development" "IDE" ];
    mimeType = [
      "text/plain"
      "inode/directory"
    ];
    actions = {
      new-empty-window = {
        name = "New Empty Window";
        exec = "/home/achim/.local/bin/codium --new-window %F";
      };
    };
  };

  # --- BROWSER (Mullvad Browser) ---
  # Mullvad Browser: Maximum Anti-Fingerprinting (basiert auf Tor Browser)
  # WICHTIG: Minimale Konfiguration! Zu viele Änderungen verschlechtern den Fingerprint.
  # Profile: ~/.mullvad/Browser/
  #
  # ⚠️ EXTENSIONS NICHT EMPFOHLEN!
  # Jede Extension macht dich uniquer und verschlechtert den Fingerprint.
  # Mullvad Browser ist für maximale Anonymität ohne Extensions konzipiert.
  #
  # Falls Extensions trotzdem gewünscht (nicht empfohlen):
  # 1. Mullvad Browser öffnen
  # 2. about:config → xpinstall.signatures.required = false
  # 3. Extensions manuell installieren
  #
  # Für alltägliche Nutzung mit Extensions: LibreWolf verwenden!

  home.file.".mullvad/Browser/user.js".text = ''
    // Mullvad Browser User Settings (MINIMAL!)
    // Zu viele Änderungen verschlechtern den Fingerprint!

    // Usability: Session beim Schließen NICHT löschen
    user_pref("privacy.clearOnShutdown.history", false);
    user_pref("privacy.clearOnShutdown.cookies", false);
    user_pref("privacy.clearOnShutdown.sessions", false);

    // Usability: Letzte Session wiederherstellen
    user_pref("browser.startup.page", 3);

    // KEINE weiteren Änderungen! Mullvad Browser hat perfekte Defaults.
  '';

  # --- BROWSER (LibreWolf) ---
  # LibreWolf wird über Firejail in modules/network.nix installiert und gesandboxt.
  # package = null verhindert doppelte Installation, wendet nur Settings/Extensions an.
  programs.librewolf = {
    enable = true;
    package = null; # Paket kommt via Firejail-Wrapper aus network.nix
    settings = {
      # Privacy & Fingerprinting-Schutz
      "privacy.clearOnShutdown.history" = false;
      "privacy.clearOnShutdown.cookies" = false;
      "privacy.clearOnShutdown.sessions" = false;
      "browser.startup.page" = 3;
      "xpinstall.signatures.required" = true;

      # ANTI-FINGERPRINTING (Maximum Privacy Mode)
      # DISABLED: Blocks WebAuthn/FIDO2 even with exemptedDomains
      # Trade-off: Nitrokey functionality > fingerprinting protection
      "privacy.resistFingerprinting" = false;
      "privacy.resistFingerprinting.letterboxing" = true; # Fenster-Größe normalisieren
      "privacy.resistFingerprinting.block_mozAddonManager" = true;
      # CRITICAL: Exempt domains that need WebAuthn/FIDO2 (Nitrokey)
      # resistFingerprinting blocks WebAuthn even when explicitly enabled
      "privacy.resistFingerprinting.exemptedDomains" = "gitlab.com,github.com,webauthn.io";
      "privacy.spoof_english" = 2; # Englisch vortäuschen (häufigste Sprache)
      "privacy.firstparty.isolate" = true; # Strikte Cookie-Isolation
      "privacy.trackingprotection.fingerprinting.enabled" = true;
      "privacy.trackingprotection.cryptomining.enabled" = true;
      "privacy.trackingprotection.enabled" = true;
      "privacy.trackingprotection.socialtracking.enabled" = true;

      # WebGL/Canvas komplett blockieren (Fingerprinting-Vektor)
      "webgl.disabled" = true;
      "webgl.enable-webgl2" = false;
      "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;
      "gfx.canvas.azure.backends" = "skia"; # Minimiert Canvas-Fingerprinting

      # Audio-Fingerprinting blockieren
      "media.webaudio.enabled" = false;
      "media.audiochannel.audioCompeting.backgroundPlaybackMuted" = true;

      # Fonts & Hardware-Fingerprinting (MAXIMUM PROTECTION)
      "gfx.font_rendering.opentype_svg.enabled" = false;
      "gfx.downloadable_fonts.enabled" = false; # Keine Web-Fonts
      "gfx.font_rendering.graphite.enabled" = false; # Graphite Fonts deaktivieren
      "layout.css.font-visibility.enabled" = true; # Font-Visibility API
      "layout.css.font-visibility.standard" = 1; # Nur Standard-Fonts exposieren
      "layout.css.font-visibility.private" = 1; # System-Fonts verstecken
      "layout.css.font-visibility.trackingprotection" = 1;
      "media.peerconnection.enabled" = false; # WebRTC komplett deaktivieren (IP-Leak)
      "media.navigator.enabled" = false; # Kein Kamera/Mikrofon-Zugriff
      "media.video_stats.enabled" = false;

      # JavaScript-basierte APIs deaktivieren (Fingerprinting-Vektoren)
      "dom.battery.enabled" = false; # Battery Status API
      # WICHTIG: Clipboard Events MÜSSEN aktiviert sein für Paste (Strg+V)!
      # "dom.event.clipboardevents.enabled" = false würde Paste brechen
      "dom.gamepad.enabled" = false; # Gamepad API
      "dom.netinfo.enabled" = false; # Network Information API
      "dom.webaudio.enabled" = false; # Web Audio API
      "dom.webnotifications.enabled" = false; # Web Notifications
      "dom.vr.enabled" = false; # WebVR
      "dom.vibrator.enabled" = false; # Vibration API
      "device.sensors.enabled" = false; # Motion/Orientation Sensors

      # HTTP Headers minimieren
      "network.http.referer.XOriginPolicy" = 2; # Nur same-origin Referer
      "network.http.referer.XOriginTrimmingPolicy" = 2; # Referer auf Origin reduzieren
      "network.http.sendRefererHeader" = 1; # Referer nur bei Klicks senden
      "network.http.sendSecureXSiteReferrer" = false;

      # User-Agent vereinheitlichen (Windows-Spoofing für bessere Anonymität)
      # WICHTIG: Diese müssen VOR resistFingerprinting gesetzt werden
      "general.useragent.override" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0";
      "general.appversion.override" = "5.0 (Windows)";
      "general.oscpu.override" = "Windows NT 10.0; Win64; x64";
      "general.platform.override" = "Win32";
      "general.buildID.override" = "20100101";

      # Geo-Location komplett deaktivieren
      "geo.enabled" = false;
      "geo.provider.network.url" = "";
      "geo.wifi.uri" = "";

      # Weitere Tracking-Schutz
      "beacon.enabled" = false; # Navigator.sendBeacon deaktivieren
      # WICHTIG: LocalStorage MUSS aktiviert bleiben für Extensions wie Bitwarden!
      # "dom.storage.enabled" = false würde Extensions brechen
      "network.cookie.cookieBehavior" = 5; # Total Cookie Protection (dFPI)

      # WebAuthn/FIDO2 für Nitrokey (GitLab, GitHub, etc.)
      # WICHTIG: Muss explizit aktiviert werden trotz Privacy-Einstellungen
      "security.webauthn.enable" = true; # WebAuthn aktivieren
      "security.webauthn.u2f" = true; # U2F-Kompatibilität (ältere FIDO2)
      "security.webauthn.webauthn_enable_usbtoken" = true; # USB-Token erlauben
      "security.webauthn.webauthn_enable_softtoken" = false; # Nur Hardware-Token
      "security.webauthn.ctap2" = true; # CTAP2-Protokoll (modern FIDO2)

      # Telemetrie & Reporting komplett deaktivieren
      "browser.safebrowsing.malware.enabled" = false;
      "browser.safebrowsing.phishing.enabled" = false;
      "browser.safebrowsing.downloads.enabled" = false;
      "browser.send_pings" = false;
      "browser.urlbar.speculativeConnect.enabled" = false;
      "network.dns.disablePrefetch" = true;
      "network.prefetch-next" = false;
      "network.predictor.enabled" = false;
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

                # uBlock Origin Built-in
                "ublock-filters" # uBlock Base
                "ublock-badware" # Malware Protection
                "ublock-privacy" # Privacy Protection
                "ublock-unbreak" # Fixes für kaputte Seiten

                # Ads & Tracking
                "easylist" # EasyList (Ads)
                "easyprivacy" # EasyPrivacy (Tracking)
                "DEU-0" # EasyList Germany (Deutsche Seiten!)
                "plowe-0" # Peter Lowe's Ad and tracking server list

                # AdGuard (Ergänzung zu EasyList)
                "adguard-generic" # AdGuard Base Filter
                "adguard-spyware" # AdGuard Spyware & Tracking
                "adguard-mobile" # AdGuard Mobile Ads (auch für Responsive Sites)

                # Cookie-Banner
                "ublock-cookies-easylist" # EasyList Cookie List
                "ublock-cookies-adguard" # AdGuard Cookie Notices
                "fanboy-cookiemonster" # Fanboy's Cookie Monster List

                # Annoyances (Popups, Newsletter, Social Widgets)
                "ublock-annoyances" # uBlock Annoyances
                "fanboy-annoyance" # Fanboy's Annoyances (Popups, Overlays)
                "fanboy-social" # Fanboy's Social Blocking (Social Media Widgets)

                # Malware & Security
                "urlhaus-1" # Online Malicious URL Blocklist (URLhaus)
                "curben-phishing" # Phishing URL Blocklist
              ];
            };
          };
        };
      };
    };
  };


  # Bitwarden Desktop Native Messaging für Browser-Biometrics
  # desktop_proxy vermittelt zwischen Browser-Extension und Desktop-App
  home.file.".librewolf/native-messaging-hosts/com.8bit.bitwarden.json".text = builtins.toJSON {
    name = "com.8bit.bitwarden";
    description = "Bitwarden desktop <-> browser bridge";
    path = "${pkgs.bitwarden-desktop}/libexec/desktop_proxy";
    type = "stdio";
    allowed_extensions = [ "{446900e4-71c2-419f-a6a7-df9c091e268b}" ];
  };

  # Librewolf Extensions (da package=null werden policies nicht automatisch angewendet)
  # Diese Datei wird von Librewolf beim Start gelesen
  home.file.".librewolf/distribution/policies.json".text = builtins.toJSON {
    policies = {
      ExtensionSettings = {
        # Bitwarden (mit Desktop-App für Biometrics)
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          granted_optional_permissions = [ "nativeMessaging" ];
        };
      };
    };
  };

  # --- VSCODIUM BUBBLEWRAP WRAPPER ---
  # Bubblewrap-Sandbox für VSCodium - Isoliert vom Rest des Systems
  # Integriertes Terminal funktioniert nicht (hardened Kernel + Electron PTY Issue)
  # Nutze externes Terminal: Strg+Shift+C
  home.file.".local/bin/codium" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Bubblewrap-Sandbox für VSCodium
      exec ${pkgs.bubblewrap}/bin/bwrap \
        --ro-bind /nix/store /nix/store \
        --dev-bind /dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --bind "$HOME" "$HOME" \
        --ro-bind /etc /etc \
        --ro-bind /run/current-system /run/current-system \
        --bind /run/user/$(id -u) /run/user/$(id -u) \
        --ro-bind /sys /sys \
        --setenv PATH "/run/wrappers/bin:/home/achim/.local/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin" \
        --unshare-pid \
        --die-with-parent \
        ${pkgs-unstable.vscodium}/bin/codium \
          --no-sandbox \
          --disable-gpu-sandbox \
          --disable-seccomp-filter-sandbox \
          "$@"
    '';
  };

  # --- GNOME KEYRING RESTORE SCRIPT ---
  home.file.".local/bin/restore-keyring" = {
    executable = true;
    text = ''
      #!/bin/sh
      # GNOME Keyring Restore Script
      # Stellt den Keyring aus einem Backup wieder her

      set -e

      BACKUP_DIR="$HOME/.local/share/keyrings/backups"
      KEYRING_DIR="$HOME/.local/share/keyrings"

      # Prüfe ob Backups existieren
      if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/keyring-backup-*.tar.gz 2>/dev/null)" ]; then
        echo "FEHLER: Keine Keyring-Backups gefunden in $BACKUP_DIR"
        exit 1
      fi

      # Liste verfügbare Backups
      echo "Verfügbare Keyring-Backups:"
      ls -1t "$BACKUP_DIR"/keyring-backup-*.tar.gz | nl

      # Wähle neuestes Backup (kann später interaktiv gemacht werden)
      LATEST_BACKUP=$(ls -1t "$BACKUP_DIR"/keyring-backup-*.tar.gz | head -1)
      echo ""
      echo "Stelle neuestes Backup wieder her: $(basename "$LATEST_BACKUP")"
      echo ""
      echo "WARNUNG: Dies überschreibt den aktuellen Keyring!"
      echo "Drücke Enter zum Fortfahren oder Strg+C zum Abbrechen..."
      read

      # GNOME Keyring beenden (damit Dateien nicht gesperrt sind)
      echo "Beende GNOME Keyring..."
      ${pkgs.procps}/bin/pkill -u $USER gnome-keyring-daemon || true
      sleep 2

      # Aktuellen Keyring sichern (für den Fall dass Restore fehlschlägt)
      echo "Sichere aktuellen Keyring..."
      ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/keyring-before-restore-$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S).tar.gz" \
        -C "$KEYRING_DIR" \
        --exclude="backups" \
        . 2>/dev/null || true

      # Restore Backup
      echo "Stelle Backup wieder her..."
      ${pkgs.gnutar}/bin/tar -xzf "$LATEST_BACKUP" -C "$KEYRING_DIR"

      echo ""
      echo "Keyring erfolgreich wiederhergestellt!"
      echo "Bitte neu einloggen (Logout/Login) damit der Keyring neu geladen wird."
    '';
  };

  # --- TOTP SCRIPT (Nitrokey → Clipboard) ---
  home.file.".local/bin/totp-posteo" = {
    executable = true;
    text = ''
      #!/bin/sh
      CODE=$(${pkgs-unstable.pynitrokey}/bin/nitropy nk3 secrets get-otp "posteo" 2>/dev/null)
      if [ -n "$CODE" ]; then
        # Code in Zwischenablage kopieren
        echo -n "$CODE" | ${pkgs.wl-clipboard}/bin/wl-copy

        # Kurzes Delay um sicherzustellen, dass wl-copy fertig ist
        sleep 0.2

        # Notification erst NACH erfolgreichem Copy
        ${pkgs.libnotify}/bin/notify-send "Posteo TOTP" "Code in Zwischenablage kopiert (Strg+V)" --icon=dialog-password -t 5000

        # Clipboard nach 30s leeren (Sicherheit)
        (sleep 30 && echo -n "" | ${pkgs.wl-clipboard}/bin/wl-copy) &
      else
        ${pkgs.libnotify}/bin/notify-send "Posteo TOTP" "Fehler: Nitrokey nicht erreichbar oder Touch nicht bestaetigt" --icon=dialog-error -t 5000
      fi
    '';
  };

  # --- WEZTERM KONFIGURATION ---
  # GNOME handelt Fensterdekorationen (Server-Side Decorations)
  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require 'wezterm'
    local config = {}

    -- Wayland-Support aktivieren, aber GNOME Decorations verwenden
    config.enable_wayland = true
    config.enable_tab_bar = true
    config.use_fancy_tab_bar = true
    config.window_decorations = "RESIZE"

    -- Farb-Schema
    config.color_scheme = 'Tokyo Night'

    -- Font
    config.font = wezterm.font('Hack Nerd Font Mono')
    config.font_size = 11.0

    return config
  '';

  # --- CA-ZERTIFIKATE FÜR FLATPAK APPS (Flare) ---
  home.file.".local/share/ca-certificates/ca-bundle.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # --- EASYEFFECTS COMMUNITY PRESETS (JackHack96) ---
  home.file.".config/easyeffects/output" = {
    source = "${easyeffects-presets}/output";
    recursive = true;
  };
  home.file.".config/easyeffects/irs" = {
    source = "${easyeffects-presets}/irs";
    recursive = true;
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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
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
      # VSCodium über Bubblewrap-Wrapper (wird von ~/.local/bin/codium bereitgestellt)
      # Alias nicht nötig, da ~/.local/bin bereits im PATH ist
      # Sonstiges
      obb = "openbb"; # FHS-wrapped, installiert automatisch beim ersten Start
      nrs = "sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos";
      charge = "sudo tlp fullcharge";
    };
    environmentVariables = {
      EDITOR = "vim";
      NPM_CONFIG_PREFIX = "~/.npm-global";
      SOPS_AGE_KEY_FILE = "~/.config/sops/age/keys.txt";
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

  # ==========================================
  # PROTONVPN GUI - Manuelle Serverauswahl
  # ==========================================
  # HYBRID MODE: CLI (systemd) verbindet beim Boot, GUI für manuellen Serverwechsel
  #
  # WICHTIG: In der GUI DEAKTIVIEREN:
  # 1. ProtonVPN GUI öffnen → Settings → Advanced
  # 2. "Auto-connect" DEAKTIVIEREN (verhindert Konflikte mit CLI)
  # 3. "Kill Switch" DEAKTIVIEREN (wird von Firewall gehandhabt)
  #
  # GUI Verwendung:
  # - Zum Serverwechsel: Disconnect vom CLI-VPN, dann in GUI anderen Server wählen
  # - Nach GUI-Disconnect: Systemd startet CLI-VPN automatisch neu
  #
  # AUTOSTART DEAKTIVIERT - GUI nur bei Bedarf manuell starten
  # systemd.user.services.protonvpn-gui = {
  #   Unit = {
  #     Description = "ProtonVPN GUI";
  #     After = [ "graphical-session.target" "network-online.target" ];
  #     PartOf = [ "graphical-session.target" ];
  #   };
  #   Service = {
  #     Type = "simple";
  #     ExecStart = "${pkgs.protonvpn-gui}/bin/protonvpn-app";
  #     Restart = "on-failure";
  #     RestartSec = "5s";
  #   };
  #   Install = {
  #     WantedBy = [ "graphical-session.target" ];
  #   };
  # };

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

      # Deklarative Ordner-Konfiguration (persistiert über Rebuilds)
      folders = {
        "Camera" = {
          id = "g7mjx-p1dto";
          path = "~/Camera";
          devices = [ "handy" ];
        };
        "Google-camera" = {
          id = "15egt-hkwhy";
          path = "~/Google-camera";
          devices = [ "handy-google" ];
        };
        "Logseq" = {
          id = "mysej-smttg";
          path = "~/Dokumente/Logseq";
          devices = [ "handy" ];
        };
        "Documents-graphene" = {
          id = "t40k6-q89pb";
          path = "~/Documents-graphene";
          devices = [ "handy" ];
        };
      };
    };
  };
}
