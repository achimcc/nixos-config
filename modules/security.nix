# Kernel & System Hardening
# Zusätzliche Sicherheitsmaßnahmen auf Kernel-Ebene

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # HARDENED KERNEL
  # ==========================================

  # Gehärteter Kernel mit zusätzlichen Schutzmaßnahmen
  boot.kernelPackages = pkgs.linuxPackages_hardened;

  # ==========================================
  # KERNEL HARDENING
  # ==========================================

  boot.kernel.sysctl = {
    # User Namespaces erlauben (benötigt für Electron-Apps wie VSCodium, Signal)
    # Der hardened Kernel deaktiviert dies standardmäßig
    "kernel.unprivileged_userns_clone" = 1;

    # Kernel Pointer verstecken (erschwert Exploits)
    "kernel.kptr_restrict" = 2;

    # Dmesg nur für root (verhindert Info-Leaks)
    "kernel.dmesg_restrict" = 1;

    # Performance Events einschränken
    "kernel.perf_event_paranoid" = 3;

    # Kexec deaktivieren (verhindert Kernel-Austausch zur Laufzeit)
    "kernel.kexec_load_disabled" = 1;

    # Unprivilegierte User dürfen keine BPF nutzen
    "kernel.unprivileged_bpf_disabled" = 1;

    # BPF JIT Hardening
    "net.core.bpf_jit_harden" = 2;

    # Ptrace einschränken (nur Parent darf Child tracen)
    "kernel.yama.ptrace_scope" = 1;

    # ASLR maximieren
    "kernel.randomize_va_space" = 2;

    # Symlink/Hardlink Schutz
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;

    # Core Dumps einschränken
    "fs.suid_dumpable" = 0;

    # ==========================================
    # NETZWERK HARDENING
    # ==========================================

    # SYN Flood Schutz
    "net.ipv4.tcp_syncookies" = 1;

    # Source Routing deaktivieren
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;

    # ICMP Redirects ignorieren
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;

    # Keine ICMP Redirects senden
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;

    # Bogus ICMP Responses ignorieren
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # Reverse Path Filtering (bereits loose für VPN)
    # "net.ipv4.conf.all.rp_filter" = 1; # Nicht setzen wegen VPN

    # TCP Timestamps deaktivieren (verhindert OS-Fingerprinting)
    "net.ipv4.tcp_timestamps" = 0;
  };

  # ==========================================
  # KERNEL MODULE BLACKLIST
  # ==========================================

  boot.blacklistedKernelModules = [
    # Ungenutzte Netzwerk-Protokolle
    "dccp"
    "sctp"
    "rds"
    "tipc"

    # Ungenutzte Dateisysteme
    "cramfs"
    "freevxfs"
    "jffs2"
    "hfs"
    "hfsplus"
    "udf"

    # Firewire (potentielles DMA-Risiko)
    "firewire-core"
    "firewire-ohci"
    "firewire-sbp2"

    # Thunderbolt (falls nicht genutzt - DMA-Risiko)
    # "thunderbolt" # Auskommentiert falls Thunderbolt-Dock genutzt wird
  ];

  # ==========================================
  # ZUSÄTZLICHE SICHERHEIT
  # ==========================================

  # Kernel Image vor Modifikation schützen
  security.protectKernelImage = true;

  # Lockdown Mode (integrity = Module müssen signiert sein)
  # security.lockKernelModules = true; # Vorsicht: Kann Probleme verursachen

  # Sudo Timeout verkürzen (Default: 15min)
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=5
  '';

  # Chromium/Electron Apps benötigen Sandbox-Zugriff
  # (VSCodium, Signal, etc. funktionieren sonst nicht mit hardened Kernel)
  security.chromiumSuidSandbox.enable = true;

  # ==========================================
  # USBGUARD - Schutz vor BadUSB-Angriffen
  # ==========================================

  services.usbguard = {
    enable = true;
    dbus.enable = true;

    # Neue Geräte blockieren bis explizit erlaubt
    implicitPolicyTarget = "block";

    # Bereits angeschlossene Geräte beim Boot erlauben
    # WICHTIG: Nach erstem Boot mit `sudo usbguard generate-policy > /etc/usbguard/rules.conf`
    # eine Policy generieren, dann presentDevicePolicy auf "apply-policy" ändern
    presentDevicePolicy = "allow";

    # Regeln-Datei (wird von usbguard generate-policy erstellt)
    rules = null;
  };

  # Sicherheits-Tools verfügbar machen
  environment.systemPackages = with pkgs; [
    usbguard
    aide
    rkhunter
    chkrootkit
  ];

  # Audit Framework aktivieren (für Incident Response)
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Überwache sudo/su Nutzung
      "-w /usr/bin/sudo -p x -k sudo_usage"
      "-w /usr/bin/su -p x -k su_usage"
      # Überwache Passwort-Dateien
      "-w /etc/passwd -p wa -k passwd_changes"
      "-w /etc/shadow -p wa -k shadow_changes"
      # Überwache SSH Konfiguration
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"
    ];
  };

  # ==========================================
  # APPARMOR
  # ==========================================

  security.apparmor = {
    enable = true;
    # Zusätzliche AppArmor-Profile aus Paketen laden
    packages = with pkgs; [ apparmor-profiles ];
    # Alle Profile im Enforce-Modus
    killUnconfinedConfinables = false; # Nicht automatisch killen
  };

  # ==========================================
  # FAIL2BAN - Brute-Force Schutz
  # ==========================================

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
      factor = "4";
    };
    ignoreIP = [
      "127.0.0.0/8"
      "192.168.0.0/16" # Lokales Netzwerk nicht sperren
    ];
  };

  # ==========================================
  # AIDE - File Integrity Monitoring
  # ==========================================

  # AIDE überwacht kritische Systemdateien auf Änderungen
  # Nach Rebuild: sudo aideinit && sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  # Prüfung: sudo aide --check
  environment.etc."aide.conf".text = ''
    # AIDE Konfiguration für NixOS
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    database_new=file:/var/lib/aide/aide.db.new

    # Regel-Definitionen
    NORMAL = p+i+n+u+g+s+m+c+acl+xattrs+sha256
    DIR = p+i+n+u+g+acl+xattrs
    PERMS = p+u+g+acl+xattrs
    LOG = p+u+g+n+acl+xattrs
    CONTENT = sha256+ftype
    DATAONLY = p+n+u+g+s+acl+xattrs+sha256

    # Kritische Systemdateien überwachen
    /etc/passwd NORMAL
    /etc/shadow NORMAL
    /etc/group NORMAL
    /etc/gshadow NORMAL
    /etc/sudoers NORMAL
    /etc/ssh NORMAL

    # Boot-Verzeichnis
    /boot NORMAL

    # NixOS Konfiguration
    /etc/nixos CONTENT

    # Ausnahmen (häufig ändernde Verzeichnisse)
    !/var/log
    !/var/cache
    !/var/tmp
    !/var/lib/aide
    !/tmp
    !/proc
    !/sys
    !/dev
    !/run
    !/nix/store
    !/nix/var
    !/home
  '';

  # Systemd-Timer für regelmäßige Prüfung
  systemd.services.aide-check = {
    description = "AIDE Integrity Check";
    path = [ pkgs.aide ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --check --config=/etc/aide.conf";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.aide-check = {
    description = "Daily AIDE Integrity Check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # ==========================================
  # ROOTKIT-ERKENNUNG (rkhunter & chkrootkit)
  # ==========================================

  # rkhunter Konfiguration
  environment.etc."rkhunter.conf".text = ''
    # rkhunter Konfiguration für NixOS
    INSTALLDIR=/run/current-system/sw
    DBDIR=/var/lib/rkhunter/db
    TMPDIR=/var/lib/rkhunter/tmp
    LOGFILE=/var/log/rkhunter.log

    # NixOS-spezifische Anpassungen
    SCRIPTDIR=/run/current-system/sw/lib/rkhunter/scripts
    ALLOWHIDDENDIR=/nix
    ALLOWHIDDENDIR=/etc/.clean
    ALLOWHIDDENFILE=/etc/.gitignore
    ALLOWDEVFILE=/dev/shm/*

    # Warnungen bei verdächtigen Dateien
    ALLOW_SSH_ROOT_USER=no
    ALLOW_SSH_PROT_V1=0

    # Updates
    UPDATE_MIRRORS=1
    MIRRORS_MODE=0
    WEB_CMD=curl

    # Mail-Benachrichtigung (optional)
    # MAIL-ON-WARNING=root@localhost

    # Zusätzliche Prüfungen aktivieren
    ENABLE_TESTS=ALL
    DISABLE_TESTS=suspscan hidden_ports hidden_procs deleted_files packet_cap_apps apps

    # NixOS: Viele Binaries sind in /nix/store
    BINDIR=/run/current-system/sw/bin /run/current-system/sw/sbin /nix/store
    PKGMGR=NONE
  '';

  # rkhunter Datenbank-Verzeichnis
  systemd.tmpfiles.rules = [
    "d /var/lib/rkhunter 0750 root root -"
    "d /var/lib/rkhunter/db 0750 root root -"
    "d /var/lib/rkhunter/tmp 0750 root root -"
  ];

  # rkhunter Scan-Service
  systemd.services.rkhunter-check = {
    description = "rkhunter Rootkit Scanner";
    path = [ pkgs.rkhunter pkgs.curl pkgs.coreutils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.rkhunter}/bin/rkhunter --check --skip-keypress --report-warnings-only";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # rkhunter Datenbank-Update Service
  systemd.services.rkhunter-update = {
    description = "rkhunter Database Update";
    path = [ pkgs.rkhunter pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.rkhunter}/bin/rkhunter --update";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Wöchentlicher rkhunter Scan (Sonntag 05:00)
  systemd.timers.rkhunter-check = {
    description = "Weekly rkhunter Rootkit Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Wöchentliches rkhunter Update (Samstag 04:00)
  systemd.timers.rkhunter-update = {
    description = "Weekly rkhunter Database Update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sat *-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # chkrootkit Scan-Service
  systemd.services.chkrootkit-check = {
    description = "chkrootkit Rootkit Scanner";
    path = [ pkgs.chkrootkit ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.chkrootkit}/bin/chkrootkit";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Wöchentlicher chkrootkit Scan (Sonntag 05:30)
  systemd.timers.chkrootkit-check = {
    description = "Weekly chkrootkit Rootkit Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:30:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # ==========================================
  # CLAMAV - Antivirus Scanner
  # ==========================================

  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        # Echtzeit-Scanning für Home-Verzeichnis
        OnAccessIncludePath = [ "/home" ];
        OnAccessExcludeUname = "clamav"; # Sich selbst nicht scannen
        # Maximale Dateigröße zum Scannen (100MB)
        MaxFileSize = "100M";
        MaxScanSize = "100M";
      };
    };
    updater = {
      enable = true;
      interval = "daily";
      frequency = 1;
    };
  };
}
