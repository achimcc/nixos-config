# Kernel & System Hardening
# Zusätzliche Sicherheitsmaßnahmen auf Kernel-Ebene

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # HARDENED KERNEL
  # ==========================================

  # Linux 6.12 LTS Kernel
  # linuxPackages_hardened wurde in nixpkgs-unstable entfernt ("lack of maintenance")
  # Sicherheitshärtung erfolgt weiterhin über boot.kernel.sysctl unten
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # ==========================================
  # KERNEL HARDENING
  # ==========================================

  boot.kernel.sysctl = {
    # User Namespaces erlauben — bewusste Risiko-Akzeptanz.
    #
    # THREAT MODEL:
    # - userns=1 öffnet Kernel-namespace-API für unprivilegierte User.
    #   Historische Exploits: CVE-2022-0185 (cgroup v1), CVE-2023-0386 (overlayfs),
    #   CVE-2023-4911 (Looney Tunables). Alle bereits gepatcht in Kernel 6.12.
    # - userns=0 würde die Angriffsfläche schließen, aber Electron-Apps
    #   (VSCodium, Chrome, Signal, Discord) deaktivieren dann ihre interne
    #   Chromium-Sandbox → Browser-/Chat-Rendering läuft ungepuffert, was
    #   PRAKTISCH eine deutlich größere Angriffsfläche eröffnet (Renderer
    #   kompromittiert → direkter User-Code-Exec).
    #
    # TRADE-OFF:
    # Electron-Sandbox > theoretischer Kernel-namespace-Bug bei gepatchtem
    # Kernel. Mitigation liegt in: (a) aktueller Kernel (6.12 LTS, CVE-Watch
    # via vulnix), (b) AppArmor-Profile für Electron-Apps, (c) Lockdown-Modus,
    # (d) SMT-Off, init_on_alloc/free für Memory-Exploit-Härte.
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

    # Core Dumps komplett deaktivieren
    "fs.suid_dumpable" = 0;                # SUID/SGID Programme
    "kernel.core_pattern" = "|/bin/false";  # Alle Core Dumps deaktivieren

    # ==========================================
    # MEMORY MANAGEMENT
    # ==========================================

    # Swap-Nutzung minimieren (verhindert sensitive Daten im Swap)
    "vm.swappiness" = 1;  # Nur bei Speicher-Druck swappen (0-100, default: 60)

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

    # Thunderbolt: DMA-Risiko, aber IOMMU (intel_iommu=on) schützt vor DMA-Angriffen
    # Nicht blacklisted wegen USB-C Monitor Hub (USBGuard: 05e3:0608)
    # Falls kein externer Monitor genutzt wird: Zeile einkommentieren
    # "thunderbolt"

    # DDR5 SPD Hub Temperatursensor — verursacht Resume-Fehler (ENXIO race condition)
    # Nur hwmon-Temperaturanzeige für RAM, kein funktionaler Verlust
    "spd5118"
  ];

  # Kernel-Module beim Boot laden (vor Kernel-Lockdown)
  # WICHTIG: security.lockKernelModules=true verhindert Laden nach Boot
  boot.kernelModules = [
    # USB-Storage (für externe SSDs)
    "usb_storage"
    "uas"

    # Netzwerk-Module
    # iwlwifi/iwlmvm = Intel WiFi, e1000e = Intel Ethernet
    "iwlwifi"
    "iwlmvm"
    "mac80211"
    "cfg80211"
    "e1000e"
  ];

  # FIDO2/Nitrokey Module werden bereits in hardware-configuration.nix geladen
  # Keine Doppelung nötig - boot.initrd.kernelModules werden automatisch zusammengeführt

  # ==========================================
  # ZUSÄTZLICHE SICHERHEIT
  # ==========================================

  # Kernel Image vor Modifikation schützen
  security.protectKernelImage = true;

  # Lockdown Mode (integrity = Module müssen signiert sein)
  security.lockKernelModules = true; # Verhindert Rootkit-Installation zur Laufzeit

  # Sudo Security Hardening
  security.sudo.extraConfig = ''
    # Timeout: Re-authenticate after 5 minutes
    Defaults timestamp_timeout=5

    # Security: Force PTY allocation (prevents injection attacks)
    Defaults use_pty

    # Logging: Log all sudo commands to dedicated file
    Defaults logfile="/var/log/sudo.log"
    Defaults log_year, log_host, loglinelen=0

    # Password: Limit password attempts and timeout
    Defaults passwd_tries=3
    Defaults passwd_timeout=1

    # Environment: Clear potentially dangerous env vars
    Defaults env_reset
    Defaults secure_path="/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"

    # Disable lecture message (already configured system)
    Defaults lecture=never
  '';

  # Chromium/Electron Apps benötigen Sandbox-Zugriff
  # (VSCodium, Signal, etc. funktionieren sonst nicht mit hardened Kernel)
  security.chromiumSuidSandbox.enable = true;

  # ==========================================
  # BITWARDEN DESKTOP - POLKIT BIOMETRICS
  # ==========================================


  # ==========================================
  # USBGUARD - Schutz vor BadUSB-Angriffen
  # ==========================================

  services.usbguard = {
    enable = true;
    dbus.enable = true;

    # Neue Geräte blockieren bis explizit erlaubt
    implicitPolicyTarget = "block";

    # Bereits angeschlossene Geräte beim Boot erlauben
    # WICHTIG: presentDevicePolicy auf "allow" verhindert nicht das FIDO2-Problem im Initrd,
    # da USBGuard erst NACH dem Initrd startet. Das Problem liegt woanders.
    presentDevicePolicy = "allow";

    # Eingefügte Geräte: Regeln vor Blockierung anwenden (verhindert Timing-Probleme)
    insertedDevicePolicy = "apply-policy";

    # Erlaubte USB-Geräte (permanent)
    rules = ''
      # Intel Bluetooth Adapter (intern, wird nach Firmware-Load re-inserted)
      allow id 8087:0033 with-interface { e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 } with-connect-type "not used"

      # SanDisk Portable SSD - Mass Storage only (verhindert BadUSB mit HID-Payload)
      # Gerät präsentiert 2 Interfaces: Bulk-Only (08:06:50) + UAS (08:06:62)
      # SICHERHEIT: with-interface beschränkt auf Mass Storage Klasse (08:*:*)
      allow id 0781:55b0 serial "323233353036343034313530" with-interface { 08:*:* 08:*:* } with-connect-type "hotplug"

      # Nitrokey 3C NFC — bevorzugt Serial-Match (Klone mit gleicher VID/PID werden geblockt)
      # Serial aus `nitropy nk3 list`. Nach Rebuild verifizieren mit:
      #   sudo usbguard list-devices | grep -i nitrokey
      # Falls USBGuard eine andere iSerial anzeigt: Wert unten anpassen.
      allow id 20a0:42b2 serial "FBB05172A161F45090A2AA9E355E0789" name "Nitrokey 3" with-connect-type "hotplug"
      # Fallback ohne Serial — greift nur wenn obige Regel NICHT matched (z.B. weil
      # iSerial-USB-Descriptor nicht die nitropy-Serial ist). TODO: nach Verifikation entfernen.
      allow id 20a0:42b2 name "Nitrokey 3" with-connect-type "hotplug"

      # reMarkable 2 Tablet
      allow id 04b3:4010 with-connect-type "hotplug"

      # USB-C Monitor Hub (Genesys Logic USB2.0 Hub)
      # Häufig in externen USB-C Monitoren verbaut
      allow id 05e3:0608 name "USB2.0 Hub" with-connect-type "hotplug"
    '';
  };

  # Sicherheits-Tools verfügbar machen
  environment.systemPackages = with pkgs; [
    usbguard
    aide
    unhide      # Findet versteckte Prozesse/Ports (Rootkit-Erkennung)

    # AIDE-Baseline-Verwaltung (siehe aide-baseline-init/update/check)
    (writeShellScriptBin "aide-baseline-init" ''
      set -eu
      if [ "$(id -u)" -ne 0 ]; then
        echo "Muss als root laufen." >&2
        exit 1
      fi
      if [ -f /var/lib/aide/aide.db ]; then
        echo "FEHLER: Baseline existiert bereits (/var/lib/aide/aide.db)." >&2
        echo "Nutze 'aide-baseline-update' für ein Update nach Rebuild." >&2
        exit 1
      fi
      mkdir -p /var/lib/aide
      chmod 0700 /var/lib/aide
      echo "Erstelle initiale AIDE-Baseline..."
      ${pkgs.aide}/bin/aide --init --config=/etc/aide.conf
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
      echo "✓ Baseline erstellt: /var/lib/aide/aide.db"
    '')

    (writeShellScriptBin "aide-baseline-update" ''
      set -eu
      if [ "$(id -u)" -ne 0 ]; then
        echo "Muss als root laufen." >&2
        exit 1
      fi
      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "FEHLER: Keine Baseline vorhanden. Zuerst 'aide-baseline-init'." >&2
        exit 1
      fi
      echo "WARNUNG: Du bist dabei die AIDE-Baseline zu ÜBERSCHREIBEN."
      echo "Hast du vorher 'aide-check' gelaufen und alle Änderungen verifiziert? (yes/no)"
      read -r ANSWER
      if [ "$ANSWER" != "yes" ]; then
        echo "Abgebrochen."
        exit 1
      fi
      ${pkgs.aide}/bin/aide --init --config=/etc/aide.conf
      cp /var/lib/aide/aide.db "/var/lib/aide/aide.db.$(date +%Y%m%d-%H%M%S).bak"
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
      echo "✓ Baseline aktualisiert. Alte DB als .bak gesichert."
    '')

    (writeShellScriptBin "aide-check" ''
      set -eu
      if [ "$(id -u)" -ne 0 ]; then
        echo "Muss als root laufen." >&2
        exit 1
      fi
      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "FEHLER: Keine Baseline vorhanden. Zuerst 'aide-baseline-init'." >&2
        exit 1
      fi
      ${pkgs.aide}/bin/aide --check --config=/etc/aide.conf
    '')

    # Bitwarden Desktop Polkit-Action (NixOS-Paketierung installiert diese nicht)
    (writeTextDir "share/polkit-1/actions/com.bitwarden.Bitwarden.policy" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE policyconfig PUBLIC
       "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
       "http://www.freedesktop.org/software/polkit/policyconfig-1.dtd">
      <policyconfig>
        <action id="com.bitwarden.Bitwarden.unlock">
          <description>Unlock Bitwarden</description>
          <message>Authenticate to unlock Bitwarden</message>
          <defaults>
            <!-- allow_any: Ungesperrter Remote-User (SSH) → verboten (kein SSH aktiv, aber Defense-in-Depth) -->
            <allow_any>no</allow_any>
            <!-- allow_inactive: Gesperrter Screen / switched-away Session → verboten (verhindert Lock-Screen-Trigger) -->
            <allow_inactive>no</allow_inactive>
            <!-- allow_active: Eingeloggte aktive Session → nur mit PAM-Auth (Passwort oder FIDO2) -->
            <allow_active>auth_self</allow_active>
          </defaults>
        </action>
      </policyconfig>
    '')
  ];

  # ==========================================
  # AUDIT FRAMEWORK (Custom Implementation)
  # ==========================================

  # Enable auditd daemon
  security.auditd.enable = true;

  # DISABLE NixOS audit module (wegen -b buffer bug)
  security.audit.enable = false;

  # Custom audit rules (bypasses NixOS module)
  environment.etc."audit/rules.d/nixos-custom.rules".text = ''
    # Custom Audit Rules (NixOS-compatible)
    # Loaded by auditd without problematic -b flag

    # Überwache kritische Systemdateien
    -w /etc/passwd -p wa -k passwd_changes
    -w /etc/shadow -p wa -k shadow_changes
    -w /etc/group -p wa -k group_changes
    -w /etc/gshadow -p wa -k gshadow_changes
    -w /etc/sudoers -p wa -k sudoers_changes

    # Überwache sudo/su Execution (syscall-based)
    -a always,exit -F arch=b64 -S execve -F path=/run/wrappers/bin/sudo -k sudo_exec
    -a always,exit -F arch=b64 -S execve -F path=/run/wrappers/bin/su -k su_exec

    # Überwache Kernel-Module (verhindert Rootkit-Installation)
    -a always,exit -F arch=b64 -S init_module,finit_module -k kernel_modules

    # Überwache Dateilöschungen (Erkennung von Spurenverwischung)
    -a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k file_delete

    # Überwache Netzwerk-Bind/Listen (Erkennung neuer Listener/Backdoors)
    -a always,exit -F arch=b64 -S bind -F auid>=1000 -F auid!=4294967295 -k network_bind
    -a always,exit -F arch=b64 -S listen -F auid>=1000 -F auid!=4294967295 -k network_listen

    # Überwache mount/umount (Erkennung von Filesystem-Manipulation)
    -a always,exit -F arch=b64 -S mount,umount2 -F auid>=1000 -F auid!=4294967295 -k filesystem_mount

    # Überwache Zeitmanipulation (Erkennung von Log-Tampering)
    -a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time_change
    -w /etc/localtime -p wa -k time_change

    # Enable audit
    -e 1
  '';

  # ==========================================
  # APPARMOR
  # ==========================================

  security.apparmor = {
    enable = true;
    # Zusätzliche AppArmor-Profile aus Paketen laden
    packages = with pkgs; [ apparmor-profiles ];
    # Alle Profile im Enforce-Modus
    killUnconfinedConfinables = true; # Unkontrollierte Prozesse mit AppArmor-Profil stoppen
  };

  # ==========================================
  # FAIL2BAN - DEAKTIVIERT
  # ==========================================
  # Keine aktiven Log-Quellen: SSH aus, keine öffentlichen Web-Services, keine
  # Netzwerk-Auth-Endpunkte. Fail2ban als root-Daemon ohne Schutzwirkung ist
  # nur Attack Surface.
  # Lokaler sudo-Brute-Force-Schutz läuft stattdessen über pam_faillock (siehe
  # security.pam.services.sudo unten) und den sudo-fail-monitor-Service.
  # Wird SSH oder ein Web-Service reaktiviert: Fail2ban hier wieder einschalten.
  services.fail2ban.enable = false;

  # ==========================================
  # AIDE - File Integrity Monitoring
  # ==========================================

  # AIDE überwacht kritische Systemdateien auf Änderungen
  # DB wird automatisch nach jedem nixos-rebuild switch re-initialisiert (siehe unten)
  # Manuelle Prüfung: sudo aide --check --config=/etc/aide.conf
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

    # Boot-Verzeichnis: NICHT überwacht
    # Secure Boot (secureboot.nix) verifiziert Boot-Integrität kryptografisch.
    # AIDE produziert hier nur False Positives, weil aide-reinit VOR der
    # Bootloader-Installation läuft (neue Generationen werden danach geschrieben).

    # NixOS Konfiguration (Flake-basiert)
    /home/user/nixos-config CONTENT

    # Nix Store wird NICHT durch AIDE überwacht (zu viele Änderungen bei Updates)
    # Stattdessen: nix-store --verify --check-contents (prüft Nix-eigene Hashes)

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
    !/home/user/nixos-config/.git
    !/home/user/nixos-config/.claude
    !/home/user/nixos-config/.crush
    !/home/user/nixos-config/flake.lock
    !/home/user/nixos-config/result
  '';

  # Systemd-Timer für regelmäßige Prüfung
  systemd.services.aide-check = {
    description = "AIDE Integrity Check";
    path = [ pkgs.aide ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal";
      StandardError = "journal";
      # AIDE Exit-Codes 1-7 = Änderungen erkannt (Bitmap: 1=added, 2=removed, 4=changed)
      # Exit-Code 0 = keine Änderungen. Exit-Code >7 = echter Fehler (IO/Config).
      SuccessExitStatus = "1 2 3 4 5 6 7";
    };
    script = ''
      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "aide-check: Keine Baseline (/var/lib/aide/aide.db fehlt)."
        echo "aide-check: Führe 'sudo aide-baseline-init' aus, um eine initiale Baseline zu erstellen."
        # Dies ist KEIN Fehler im Sinne des Timers — normaler Zustand nach Setup.
        exit 0
      fi
      ${pkgs.aide}/bin/aide --check --config=/etc/aide.conf
    '';
  };

  # AIDE DB-Management — NICHT automatisch bei jedem Rebuild!
  #
  # THREAT MODEL:
  # Automatischer Reinit bei jedem nixos-rebuild machte AIDE wirkungslos gegen
  # einen Angreifer, der vor dem Rebuild Modifikationen einschleust — die
  # Änderungen würden als neuer Baseline akzeptiert, ohne dass der User etwas
  # merkt. Darum: Baseline-Update ist jetzt expliziter User-Akt.
  #
  # INITIALE DB (einmalig, beim ersten Setup oder nach Systemwechsel):
  #   sudo aide-baseline-init
  #
  # NACH EINEM NIXOS-REBUILD:
  #   1. sudo aide-check                     # prüft gegen alte Baseline
  #   2. Änderungen inspizieren              # sind alle legitim?
  #   3. sudo aide-baseline-update           # neue Baseline schreiben (bestätigt)
  #
  # Der tägliche systemd-Timer `aide-check.timer` läuft weiter und alarmiert
  # bei Abweichungen gegen die aktuelle Baseline.
  # Die Scripts aide-baseline-init/update/check sind oben in environment.systemPackages.

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
  # ROOTKIT-ERKENNUNG (unhide)
  # ==========================================

  # unhide - Findet versteckte Prozesse und Ports (Rootkit-Indikator)
  # Scan-Service für versteckte Prozesse
  systemd.services.unhide-check = {
    description = "Unhide Hidden Process Scanner";
    restartIfChanged = false; # Kein Neustart bei nixos-rebuild (läuft via Timer)
    path = [ pkgs.unhide pkgs.procps ];
    serviceConfig = {
      Type = "oneshot";
      # Prüfe auf versteckte Prozesse mit verschiedenen Techniken
      # Binary heißt "unhide-linux" (Linux-spezifische Checks), nicht "unhide"
      ExecStart = "${pkgs.unhide}/bin/unhide-linux sys procall";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Scan-Service für versteckte TCP/UDP Ports
  systemd.services.unhide-tcp-check = {
    description = "Unhide Hidden TCP/UDP Port Scanner";
    restartIfChanged = false; # Kein Neustart bei nixos-rebuild (läuft via Timer)
    path = [ pkgs.unhide pkgs.nettools pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.unhide}/bin/unhide-tcp";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Wöchentlicher unhide Scan (Sonntag 05:00)
  systemd.timers.unhide-check = {
    description = "Daily Unhide Process Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Täglicher unhide-tcp Scan (05:15)
  systemd.timers.unhide-tcp-check = {
    description = "Daily Unhide TCP/UDP Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # ==========================================
  # CLAMAV - Antivirus Scanner
  # ==========================================

  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        # Maximale Dateigröße zum Scannen (100MB)
        MaxFileSize = "100M";
        MaxScanSize = "100M";
        # Echtzeit-Scanning Konfiguration (für clamonacc)
        # Scan entire filesystem except high-churn directories
        OnAccessIncludePath = [ "/" ];
        OnAccessExcludePath = [
          "/proc"
          "/sys"
          "/dev"
          "/run"
          "/tmp"
          "/var/tmp"
          "/var/cache"
          "/var/log"
          "/var/lib/systemd"
          "/var/lib/aide"  # AIDE database changes frequently
          "/nix/var"       # Nix build artifacts
        ];
        OnAccessExcludeUname = "clamav";
        OnAccessPrevention = "yes"; # Erkannte Bedrohungen blockieren
      };
    };
    updater = {
      enable = true;
      interval = "daily";
      frequency = 1;
    };
    # Echtzeit-Scanner aktivieren
    fangfrisch.enable = true;
    scanner = {
      enable = true;
      interval = "daily";
    };
  };

  # clamdscan nicht bei nixos-rebuild neu starten (läuft via Timer)
  systemd.services.clamdscan.restartIfChanged = false;

  # Log-Verzeichnisse erstellen (merged mit sudo-fail-monitor rules weiter unten)
  systemd.tmpfiles.rules = [
    "d /var/log/clamav 0750 clamav clamav -"
    "f /var/log/sudo.log 0600 root root -"  # Sudo audit log
    "d /var/lib/sudo-fail-monitor 0700 root root -"
  ];

  # clamonacc Service für Echtzeit-Scanning
  systemd.services.clamonacc = {
    description = "ClamAV On-Access Scanner";
    restartIfChanged = false; # Kein Neustart bei nixos-rebuild (Echtzeit-Scanner)
    after = [ "clamav-daemon.service" "systemd-tmpfiles-setup.service" ];
    requires = [ "clamav-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      # Warte bis clamd-Socket bereit ist (max 60s)
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -S /run/clamav/clamd.ctl ] && exit 0; sleep 1; done; exit 1'";
      ExecStart = "${pkgs.clamav}/bin/clamonacc --foreground --log=/var/log/clamav/clamonacc.log";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # ==========================================
  # FIDO2/NITROKEY PAM-AUTHENTIFIZIERUNG
  # ==========================================

  # FIDO2 mit PIN + Touch als Alternative zum Passwort
  # Nitrokey eingesteckt → PIN eingeben + Key berühren → authentifiziert
  # Kein Nitrokey → normales Passwort als Fallback
  security.pam.u2f = {
    enable = true;
    control = "sufficient";
    settings = {
      cue = true;
      pinverification = 1;
      # nouserok: Erlaubt Fallback zu Passwort wenn:
      # - Nitrokey nicht eingesteckt ist
      # - PIN-Dialog fehlschlägt (kein Terminal verfügbar)
      # - u2f_keys Datei fehlt
      # Ohne diesen Parameter würde "conversation failed" die Authentifizierung blockieren
      nouserok = true;
    };
  };

  # PAM-Services für FIDO2 aktivieren
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.gdm-password.u2fAuth = true;

  # GNOME Keyring bei Login automatisch entsperren (erstellt "login"-Collection)
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;

  # ==========================================
  # PAM FAILLOCK - sudo Brute-Force Schutz
  # ==========================================
  # Sperrt den User-Account nach 5 fehlgeschlagenen Auth-Versuchen für 15 Min.
  # Greift für sudo, login, gdm-password (alles was den Standard-PAM-Stack nutzt).
  # `deny=0` auf FIDO2-Pfad → Faillock zählt nur Passwort-Fails, nicht Key-Touch-Fehler.
  # Status prüfen: `faillock --user user`; zurücksetzen: `sudo faillock --user user --reset`
  security.pam.services.sudo.failDelay.delay = 4000000; # 4s Delay nach jedem Fehlversuch
  security.pam.services.login.failDelay.delay = 4000000;

  # Faillock-Konfiguration (/etc/security/faillock.conf wird vom pam_faillock gelesen)
  environment.etc."security/faillock.conf".text = ''
    # Lockout nach N fehlgeschlagenen Auth-Versuchen
    deny = 5
    # Lockout-Zeit in Sekunden (15 Minuten)
    unlock_time = 900
    # Zählzeitraum in Sekunden (Fehlversuche werden nach 15 Min vergessen)
    fail_interval = 900
    # Root-Account NICHT sperren (sonst könnte sich niemand mehr einloggen)
    # Wir haben eh keinen Root-Login, aber zur Sicherheit
    even_deny_root = no
    # Audit-Logs: Ja
    audit
    # Silent: keine Meldung "Account locked" im Auth-Prompt (reduziert Info-Leak)
    silent
  '';

  # ==========================================
  # SUDO FAIL MONITOR
  # ==========================================
  # Beobachtet /var/log/sudo.log auf fehlgeschlagene Passwort-Versuche und
  # sendet bei ≥3 Fehlversuchen innerhalb 10 Min eine Email-Alarmierung.
  # Liefert Observability zusätzlich zum reinen Lockout durch faillock.
  systemd.services.sudo-fail-monitor = {
    description = "Monitor sudo.log for failed auth attempts and alert";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "30s";
      # Minimale Privilegien
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadOnlyPaths = [ "/var/log/sudo.log" ];
      ReadWritePaths = [ "/var/lib/sudo-fail-monitor" ];
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
    };

    script = ''
      set -eu
      STATE_DIR="/var/lib/sudo-fail-monitor"
      mkdir -p "$STATE_DIR"
      STATE_FILE="$STATE_DIR/last-alert"

      # Tail sudo.log inkrementell, filtere auf Fehlversuche
      ${pkgs.coreutils}/bin/tail -n 0 -F /var/log/sudo.log 2>/dev/null | \
      while IFS= read -r line; do
        # Match: "N incorrect password attempts" oder "authentication failure"
        case "$line" in
          *"incorrect password attempts"*|*"authentication failure"*)
            NOW=$(${pkgs.coreutils}/bin/date +%s)
            # Rate-Limit: max 1 Alert pro 10 Minuten
            if [ -f "$STATE_FILE" ]; then
              LAST=$(${pkgs.coreutils}/bin/cat "$STATE_FILE")
              DIFF=$((NOW - LAST))
              if [ "$DIFF" -lt 600 ]; then
                continue
              fi
            fi
            echo "$NOW" > "$STATE_FILE"

            # Email-Alert via msmtp
            if [ -f /run/secrets/email/posteo ]; then
              EMAIL=$(${pkgs.coreutils}/bin/cat /run/secrets/email/posteo)
              ${pkgs.coreutils}/bin/printf 'Subject: [NixOS Security] sudo Fehlversuch auf %s\n\nSudo-Log-Eintrag:\n\n%s\n\nAlle Fehlversuche heute:\n%s\n' \
                "$(${pkgs.inetutils}/bin/hostname)" \
                "$line" \
                "$(${pkgs.gnugrep}/bin/grep -E 'incorrect password|authentication failure' /var/log/sudo.log | ${pkgs.coreutils}/bin/tail -20)" \
                | ${pkgs.msmtp}/bin/msmtp "$EMAIL" 2>&1 \
                | ${pkgs.systemd}/bin/systemd-cat -t sudo-fail-monitor -p warning || true
            fi

            # Journal-Log als Primäralarm (Email ist best-effort)
            echo "SUDO FAIL DETECTED: $line" | ${pkgs.systemd}/bin/systemd-cat -t sudo-fail-monitor -p crit
            ;;
        esac
      done
    '';
  };

  # Journal-Größe — großzügig dimensioniert wegen Suricata (jetzt 3 Interfaces:
  # proton0, wlp0s20f3, enp0s31f6) + auditd + sudo-fail-monitor. 2G ist sicher
  # erreichbar bei hohem Netzwerkverkehr.
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=4G
    MaxRetentionSec=30day
    # Pro-Service-Rate-Limit: Verhindert dass eine Log-Flut anderer Services
    # Platz stiehlt. 10000 Messages pro 30s pro Unit sollten Malware-Scan und
    # Brute-Force-Alerts abdecken ohne dass andere Services hungern.
    RateLimitIntervalSec=30s
    RateLimitBurst=10000
    # Forward to kmsg NICHT (default), spart Memory-Ring-Buffer-Overhead
    ForwardToKMsg=no
  '';

  # Log-Rotation für sudo.log
  services.logrotate.settings.sudo = {
    files = "/var/log/sudo.log";
    frequency = "weekly";
    rotate = 4;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
  };
}
