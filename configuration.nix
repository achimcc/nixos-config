# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Importiert den Home Manager als NixOS Modul
      <home-manager/nixos>
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b".device = "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
  networking.hostName = "nixos"; # Define your hostname.

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "de_DE.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account.
  users.users.user = {
    isNormalUser = true;
    description = "NixOS User";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
    # Nushell als Standard-Login-Shell setzen
    shell = pkgs.nushell;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    git
    # Nushell muss auch global verfügbar sein
    nushell
  ];

  # ==========================================
  # HOME MANAGER KONFIGURATION
  # ==========================================

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Start des Home-Manager Blocks für User "user"
  home-manager.users.user = { pkgs, ... }: {

    home.stateVersion = "24.11";

    # WICHTIG FÜR RUST:
    # Fügt ~/.cargo/bin zum Pfad hinzu, damit 'cargo', 'rustc' etc. gefunden werden.
    home.sessionPath = [ "$HOME/.cargo/bin" ];

    # User-spezifische Pakete
    home.packages = with pkgs; [

      # --- SICHERHEIT & TOOLS ---
      keepassxc
      kdePackages.kleopatra

      # --- NIX ENTWICKLUNG ---
      nil
      nixpkgs-fmt

      # --- RUST ENTWICKLUNG ---
      rustup # Toolchain Manager (installiert cargo, rustc, etc.)
      gcc # Linker (cc), zwingend notwendig für Rust auf NixOS
    ];

    # --- PGP KONFIGURATION ---
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-gnome3;
      enableSshSupport = true;
    };

    # --- EMAIL CLIENT (Thunderbird - Hardened) ---
    programs.thunderbird = {
      enable = true;
      profiles = {
        "user" = {
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
      userName = "NixOS User";
      userEmail = "user@posteo.de";
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
        # Extensions installieren
        extensions = with pkgs.vscode-extensions; [
          # Nix
          jnoortheen.nix-ide

          # Rust
          rust-lang.rust-analyzer # Offizielle Rust Unterstützung
          tamasfe.even-better-toml # Syntax Highlighting für Cargo.toml
          vadimcn.vscode-lldb # Debugger für Rust
        ];

        # VS Code Einstellungen (settings.json)
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
          # Nutze Clippy statt Check für bessere Warnungen
          "rust-analyzer.check.command" = "clippy";
          # Pfad explizit angeben, damit VSCode nicht versucht Binaries herunterzuladen
          "rust-analyzer.server.path" = "rust-analyzer";
          # Debugger Pfad
          "lldb.executable" = "lldb";

          # VS Code Terminal auf Nushell setzen
          "terminal.integrated.defaultProfile.linux" = "nushell";
          "terminal.integrated.profiles.linux" = {
            "nushell" = {
              "path" = "${pkgs.nushell}/bin/nu";
            };
          };
        };
      };
    };

    # --- BROWSER (LibreWolf) ---
    programs.librewolf = {
      enable = true;
      settings = {
        "privacy.clearOnShutdown.history" = false;
        "privacy.resistFingerprinting" = false;
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.sessions" = false;
        "browser.startup.page" = 3;
      };
      policies = {
        ExtensionSettings = {
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

    # --- SHELL CONFIGURATION (Innerhalb von home-manager) ---

    # 1. Starship: Der moderne Prompt (Cross-Shell)
    programs.starship = {
      enable = true;
      # Integration für Nushell automatisch aktivieren
      enableNushellIntegration = true;
    };

    # 2. Carapace: Multi-Shell Argument Completer
    # Sorgt dafür, dass TAB-Vervollständigung für git, docker, cargo etc. funktioniert
    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
    };

    # 3. Nushell: Die Shell selbst
    programs.nushell = {
      enable = true;
      # Konfiguration für Aliase und Umgebungsvariablen
      shellAliases = {
        ll = "ls -l";
        la = "ls -a";
        # Git Abkürzungen
        gs = "git status";
        gc = "git commit";
        gp = "git push";
      };
      environmentVariables = {
        # Damit der Editor (z.B. bei git commit) nano oder hx ist
        EDITOR = "nano";
      };
      extraConfig = ''
        # Hier deaktivieren wir die Willkommensnachricht
        $env.config.show_banner = false
      '';
    };

  }; # <--- HIER ENDET DER HOME-MANAGER BLOCK FÜR USER user

  # This value determines the NixOS release...
  system.stateVersion = "24.11";

}
