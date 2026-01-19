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

    # --- NIX ENTWICKLUNG ---
    nil
    nixpkgs-fmt

    # --- RUST ENTWICKLUNG ---
    rustup # Enthält rust-analyzer (rustup component add rust-analyzer)
    gcc

    # --- KOMMUNIKATION ---
    signal-desktop

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

  # --- VS CODE ---
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        vadimcn.vscode-lldb
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

        # VS Code Terminal
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
      EDITOR = "nano";
    };
    extraConfig = ''
      $env.config.show_banner = false
    '';
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
