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

  # WICHTIG FÜR RUST:
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  # SSH Agent Socket für FIDO2-Schlüssel
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";
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
    fd # Schnelles find mit intuitiver Syntax
    bottom # btm - grafischer Prozess-Monitor
    xh # HTTP-Client mit JSON-Formatting
    dust # Visualisierte Festplattenbelegung
    yazi # Terminal-Dateimanager mit Vorschau

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

    # --- MEDIA PLAYER ---
    celluloid # GTK-Frontend für mpv
    amberol # GNOME Musik-Player für lokale Dateien

    # --- TERMINAL ---
    blackbox-terminal
    wezterm

    # --- NOTIZEN & ZEICHNEN ---
    rnote # Handschriftliche Notizen und Skizzen (GTK/libadwaita)

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
    llm-agents.packages.${pkgs.system}.crush
    # claude-code via npm installieren: npm install -g @anthropic-ai/claude-code

    # --- RESUME / CV ---
    resumed # JSON Resume builder (lightweight alternative to resume-cli)

    # --- NETWORK SIMULATOR ---
    shadow-simulator # Discrete-event network simulator für verteilte Systeme

    # --- REMARKABLE TABLET ---
    rcu.packages.${pkgs.system}.default # RCU - reMarkable Connection Utility
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

          # GNOME Online Accounts (CalDAV für GNOME Kalender)
          # GVariant-Format: {'password': <'...'> }
          printf "{'password': <'%s'>}" "$PASSWORD" | \
            ${pkgs.libsecret}/bin/secret-tool store \
              --label="GOA webdav credentials for identity account_posteo_caldav_0" \
              xdg:schema org.gnome.OnlineAccounts \
              goa-identity "webdav:gen0:account_posteo_caldav_0"
        fi
      '';
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
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
    # SSH-Keys automatisch zum Agent hinzufügen beim ersten Nutzen
    addKeysToAgent = "yes";
    matchBlocks = {
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
    };
  };

  # --- GIT ---
  programs.git = {
    enable = true;
    userName = "Achim Schneider";
    userEmail = "achim.schneider@posteo.de";
    signing = {
      key = "~/.ssh/id_ed25519_sk.pub";
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
        "terminal.integrated.defaultProfile.linux" = "nushell";
        "terminal.integrated.profiles.linux" = {
          "nushell" = {
            "path" = "${pkgs.nushell}/bin/nu";
          };
        };
        "terminal.integrated.fontFamily" = "'Hack Nerd Font Mono'";

        # Externer Terminal: Black Box
        "terminal.external.linuxExec" = "${pkgs.blackbox-terminal}/bin/blackbox";

        # -- PRIVACY --
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none"; # Updates via Nix
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
      "privacy.resistFingerprinting" = true;
      "privacy.resistFingerprinting.letterboxing" = true; # Fenster-Größe normalisieren
      "privacy.resistFingerprinting.block_mozAddonManager" = true;
      "privacy.resistFingerprinting.exemptedDomains" = ""; # Keine Ausnahmen
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
      "dom.event.clipboardevents.enabled" = false; # Clipboard Events
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
      # Sonstiges
      obb = "openbb"; # FHS-wrapped, installiert automatisch beim ersten Start
      nrs = "sudo nixos-rebuild switch --flake /home/achim/nixos-config#achim-laptop";
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
