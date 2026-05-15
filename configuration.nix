# NixOS Hauptkonfiguration für nixos
# Module werden aus ./modules/ importiert

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/network.nix
    ./modules/firewall.nix
    ./modules/protonvpn.nix
    ./modules/dns-watchdog.nix
    ./modules/desktop.nix
    ./modules/audio.nix
    ./modules/power.nix
    ./modules/suspend-monitor.nix
    ./modules/sops.nix
    ./modules/security.nix
    ./modules/apparmor-profiles.nix
    ./modules/secureboot.nix
    ./modules/suricata.nix
    ./modules/logwatch.nix
    ./modules/email-alerts.nix
    ./modules/ssh-hardening.nix
    ./modules/cve-monitoring.nix
  ];

  # ==========================================
  # BOOTLOADER (Secure Boot via Lanzaboote in modules/secureboot.nix)
  # ==========================================

  # Kernel: Linux 6.12 LTS (Standard aus modules/security.nix)
  # linuxPackages_hardened wurde in nixpkgs-unstable entfernt → gewechselt auf linuxPackages_6_12
  # WICHTIG: Kernel 6.18 führt zu GuC init failure (-5) → System bootet nicht ohne nomodeset
  # → Bleiben bei 6.12 bis Kernel-Fix für Meteor Lake verfügbar
  # boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;  # DEAKTIVIERT wegen GuC-Bug

  boot.kernelParams = [
    # IOMMU (DMA-Schutz)
    "intel_iommu=on"
    "iommu=force"

    # Memory Hardening (Exploit-Mitigation)
    "init_on_alloc=1" # Speicher bei Allokation nullen (verhindert Info-Leaks)
    "init_on_free=1" # Speicher bei Freigabe nullen (verhindert Use-After-Free)
    "page_alloc.shuffle=1" # Page-Allocator randomisieren (Anti-Exploit)
    "randomize_kstack_offset=on" # Kernel-Stack randomisieren (KASLR++)
    "slab_nomerge" # Slab-Caches nicht mergen (verhindert Exploits)

    # Kernel Lockdown
    "lockdown=integrity" # Kernel-Lockdown-Modus (verhindert unsigned Module)

    # Legacy-Features deaktivieren
    "vsyscall=none" # Vsyscall komplett deaktivieren (alt, unsicher)

    # CPU Mitigations (Spectre/Meltdown)
    "mitigations=auto,nosmt" # Alle CPU-Mitigations, SMT deaktivieren (Performance-Hit)

    # Suspend/Resume (ThinkPad T14 Gen 5 / Intel Meteor Lake)
    # BIOS unterstützt NUR s2idle (Modern Standby), KEIN S3 Deep Sleep
    # s2idle braucht tiefe CPU C-States (C6-C10) für Stromsparen
    # ENTFERNT 2026-02-28: mem_sleep_default=deep (wurde ignoriert, Firmware nur s2idle)
    # ENTFERNT 2026-02-28: intel_idle.max_cstate=1 (verhinderte tiefe C-States →
    #   Akku leer über Nacht im Suspend, da CPU in C1 blieb statt C6+)
    # Die "Resume-Freezes" von 2026-02-07 waren GPU-Crashes (jetzt via cairo/PSR=0 behoben)

    # Intel i915 Meteor Lake Stabilitätsfix (GPU device ID 7dd5)
    # PROBLEM 1: "Selective fetch area calculation failed in pipe A" → harter Crash
    # PROBLEM 2: GPU HANG ecode 12:1 (Render Engine) → SLUB Korruption → Reboot
    # URSACHE: i915 Render Engine Bug auf Meteor Lake (Kernel 6.12+)
    # - enable_psr=0: verhindert PSR-bezogene Crashes
    # - GSK_RENDERER=cairo (desktop.nix): verhindert GPU-Nutzung durch GTK4-Apps
    # - gnome-characters entfernt (desktop.nix): häufigster Crash-Trigger
    # CRASH-HISTORIE:
    #   2026-02-15: Nautilus/Vulkan → GPU HANG → Reboot
    #   2026-02-23: gnome-characters/Vulkan → GPU HANG → SLUB BUG → Reboot
    #   2026-02-27: gnome-characters/GL(!) → GPU HANG → SLUB BUG → Reboot (nach Resume)
    "i915.enable_psr=0" # PSR komplett deaktivieren (SF Crashes verhindern)
    # Falls weiterhin Crashes: "i915.enable_dc=0" als nächste Eskalation
  ];
  boot.loader.systemd-boot.configurationLimit = 10; # Weniger Boot-Einträge
  boot.loader.efi.canTouchEfiVariables = true;

  # Dateisystem-Unterstützung (Kernel-Module)
  boot.supportedFilesystems = [ "exfat" ]; # Für externe SSDs/USB-Sticks

  # ==========================================
  # LUKS Verschlüsselung
  # ==========================================

  # Systemd in Initrd (für TPM2-LUKS-Entsperrung)
  boot.initrd.systemd.enable = true;

  # TPM 2.0 für zusätzliche Boot-Sicherheit
  boot.initrd.systemd.tpm2.enable = true;

  # Root-Partition: Passphrase-Entsperrung (FIDO2-Slot ENTFERNT — Hardware-Token nicht mehr genutzt)
  # Falls der Slot in cryptsetup luksDump noch existiert, manuell entfernen:
  #   sudo systemd-cryptenroll --wipe-slot=fido2 /dev/disk/by-uuid/fcef0557-...

  # Swap: TPM2-basierte Entsperrung (für Hibernate/Resume ohne Interaktion)
  # Swap-Verschlüsselung explizit verifiziert (LUKS2)
  # MIGRATION: Von Keyfile auf TPM2 umgestellt (Keyfile auf unverschlüsselter /boot war extrahierbar)
  #
  # PCR-POLICY: 0+7+11 (Firmware + Secure-Boot-State + UKI-Measurement)
  # - PCR 0:  UEFI-Firmware (schützt gegen Firmware-Swap)
  # - PCR 7:  Secure-Boot-Keys/State (db, dbx, PK, KEK)
  # - PCR 11: Lanzaboote UKI-Hash (Kernel+Initrd+Cmdline signiert)
  # → Angreifer kann keinen manipulierten Kernel/Initrd booten, der das TPM-Secret bekommt.
  #
  # TRADE-OFF: PCR 11 ändert sich bei jedem Kernel/Initrd-Update → Re-Enroll nötig.
  # Der `tpm2-reenroll-swap`-Service (siehe unten) automatisiert das nach jedem Rebuild.
  #
  # ENROLLMENT (einmalig nach Umstellung auf 0+7+11):
  #   sudo systemd-cryptenroll --wipe-slot=tpm2 \
  #     /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
  #   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7+11 \
  #     /dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b
  #
  # FUTURE: Public-Key-Policy (--tpm2-public-key) würde Re-Enroll überflüssig
  # machen, erfordert aber UKI-Signatur-Einbettung, die Lanzaboote aktuell nicht
  # automatisiert. Siehe docs/TPM-ENROLLMENT.md.
  boot.initrd.luks.devices."luks-f8e58c55-8cf8-4781-bdfd-a0e4c078a70b" = {
    device = "/dev/disk/by-uuid/f8e58c55-8cf8-4781-bdfd-a0e4c078a70b";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
    # SICHERHEIT: allowDiscards deaktiviert (verhindert Metadata-Leaks)
    # Trade-off: Minimal schlechtere SSD-Performance, deutlich bessere Sicherheit
    allowDiscards = false;
  };

  # ==========================================
  # LOKALISIERUNG
  # ==========================================

  time.timeZone = "Europe/Berlin";
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

  # ==========================================
  # BENUTZER
  # ==========================================

  users.users.user = {
    isNormalUser = true;
    description = "NixOS User";
    extraGroups = [ "networkmanager" "wheel" "input" ];
    shell = pkgs.nushell;
  };

  # ==========================================
  # SYSTEM PAKETE
  # ==========================================

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    nushell
    libsecret
    nano # Für EDITOR Variable in nushell
    vim
    python3

    # CLI Tools
    ripgrep # Schnelles grep (rg)
    fd # Schnelles find
    fzf # Fuzzy Finder
    htop # Interaktiver Process Viewer
    dnsutils # dig, nslookup, host (DNS-Tools)

    # Dateisystem-Unterstützung
    exfatprogs # exFAT für externe SSDs/USB-Sticks

    # Archiv-Manager
    peazip # Multi-Format Archiv-Manager (ZIP, 7Z, RAR, etc.)

    # Monero Wallet
    feather # Feather Wallet (Monero)
  ];

  # ==========================================
  # FIRMWARE
  # ==========================================

  hardware.enableRedistributableFirmware = true;

  # fwupd: BIOS/Firmware-Updates über LVFS (Linux Vendor Firmware Service)
  # Ermöglicht BIOS-Updates direkt aus Linux ohne Windows/DOS-Boot
  services.fwupd.enable = true;

  # ==========================================
  # BLUETOOTH
  # ==========================================

  hardware.bluetooth.enable = true;
  # SICHERHEIT: powerOnBoot=false → BT ist bei Systemstart AUS, manuell
  # einschalten via GNOME Settings oder `bluetoothctl power on`. Reduziert
  # Angriffsfläche (BlueFrag/KNOB/BrakTooth) wenn BT nicht gebraucht wird.
  hardware.bluetooth.powerOnBoot = false;
  hardware.bluetooth.settings = {
    General = {
      # Experimental=true schaltete experimentelle BlueZ-Features frei (u.a.
      # LE-Advertisements, Battery-Profile). Nicht benötigt → off.
      Experimental = false;
      # Privacy: Nicht als Discoverable-Default
      DiscoverableTimeout = 30;
      PairableTimeout = 30;
    };
  };


  # ==========================================
  # Hardware graphics für Video Transcoding
  # ==========================================
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Wichtig für Meteor Lake (iHD)
      libvdpau-va-gl
    ];
  };

  # Lade uhid-Modul für Bluetooth HID-Geräte (Mäuse, Tastaturen)
  # Lade exfat-Modul für externe SSDs/USB-Sticks
  boot.kernelModules = [ "uhid" "exfat" ];

  # ==========================================
  # DRUCKER (Brother MFC-7360N im Netzwerk)
  # ==========================================

  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ]; # Open-Source Brother Laser Treiber
  };

  # Netzwerk-Drucker Auto-Discovery
  # DEAKTIVIERT: Avahi/mDNS nicht benötigt (Drucker-IP ist in firewall.nix hardcoded)
  # Behebt Suricata-Warnung "MDNS protocol in use"
  services.avahi = {
    enable = false;
  };

  # ==========================================
  # FLATPAK (für Signal Desktop - braucht keine User Namespaces)
  # ==========================================

  services.flatpak.enable = true;

  # ==========================================
  # TOR
  # ==========================================
  # Tor-Daemon abgeschaltet (nicht aktiv genutzt → Attack Surface).
  # tor-browser bleibt verfügbar (startet eigenen Tor-Prozess pro Session).
  services.tor.enable = false;
  services.tor.client.enable = false;

  # ==========================================
  # TAILSCALE VPN
  # ==========================================
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client"; # Erlaubt Exit Nodes von anderen Tailscale-Geräten zu nutzen
    extraUpFlags = [ "--accept-routes" ];
  };

  # Deaktiviert Tailscale's eigene iptables-Verwaltung (--nfmask nicht kompatibel mit iptables-nft).
  # Equivalent nftables-Regeln sind in modules/firewall.nix (ts-nat + forward chain).
  systemd.services.tailscale-netfilter-off = {
    description = "Set Tailscale netfilter-mode to off";
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale set --netfilter-mode=off";
    };
  };

  # ==========================================
  # SSD OPTIMIERUNG
  # ==========================================

  services.fstrim.enable = true;

  # ==========================================
  # NIX EINSTELLUNGEN
  # ==========================================

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    max-jobs = "auto";
    cores = 0; # Alle Kerne nutzen
  };

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ==========================================
  # AUTOMATISCHE UPDATE-BENACHRICHTIGUNGEN
  # ==========================================

  # SICHERHEIT: Automatische Updates deaktiviert (manuelle Kontrolle bevorzugt)
  # Stattdessen: Benachrichtigung bei verfügbaren Updates
  system.autoUpgrade.enable = false;

  # Systemd-Service: Prüft täglich auf Updates und benachrichtigt
  systemd.services.notify-updates = {
    description = "Check for NixOS Updates and Notify";
    serviceConfig = {
      Type = "oneshot";
      User = "user";
    };

    script = ''
      cd /home/user/nixos-config

      # Flake-Inputs aktualisieren (nur lokal, kein rebuild)
      ${pkgs.nix}/bin/nix flake update --commit-lock-file 2>&1 | tee /tmp/flake-update.log

      # Prüfe ob Updates verfügbar sind
      if ${pkgs.git}/bin/git diff --quiet flake.lock; then
        # Keine Updates
        echo "No updates available"
      else
        # Updates verfügbar - Benachrichtigung senden
        DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
          ${pkgs.libnotify}/bin/notify-send \
          --urgency=normal \
          --icon=software-update-available \
          "NixOS Updates verfügbar" \
          "Neue Flake-Updates wurden heruntergeladen. Rebuild mit: sudo nixos-rebuild switch"

        echo "Updates available - notification sent"
      fi
    '';
  };

  systemd.timers.notify-updates = {
    description = "Daily NixOS Update Check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # ==========================================
  # ZUSÄTZLICHE CA-ZERTIFIKATE
  # ==========================================

  # Signal Messenger nutzt eigene Root-CA für chat.signal.org
  # Siehe: https://github.com/signalapp/Signal-Desktop/issues/6707
  security.pki.certificateFiles = [
    ./ca-certificates/signal-messenger.pem
  ];

  # ==========================================
  # STATE VERSION - NICHT ÄNDERN!
  # ==========================================

  system.stateVersion = "24.11";


  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
  ];
}
