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

    # Thunderbolt (falls nicht genutzt - DMA-Risiko)
    # "thunderbolt" # Auskommentiert falls Thunderbolt-Dock genutzt wird
  ];

  # USB-Storage Module explizit laden (für externe SSDs)
  boot.kernelModules = [ "usb_storage" "uas" ];

  # FIDO2/Nitrokey Module im Initrd laden (vor Kernel-Lockdown und USBGuard)
  boot.initrd.kernelModules = [ "usbhid" "hid_generic" ];

  # ==========================================
  # ZUSÄTZLICHE SICHERHEIT
  # ==========================================

  # Kernel Image vor Modifikation schützen
  security.protectKernelImage = true;

  # Lockdown Mode (integrity = Module müssen signiert sein)
  security.lockKernelModules = true; # Verhindert Rootkit-Installation zur Laufzeit

  # Sudo Timeout verkürzen (Default: 15min)
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=5
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

      # SanDisk Portable SSD - Vereinfachte Regel für schnelleres Matching
      # Erlaubt alle SanDisk Portable SSDs (0781:55b0) per Hotplug
      allow id 0781:55b0 with-connect-type "hotplug"

      # Nitrokey 3C NFC
      allow id 20a0:42b2 name "Nitrokey 3" with-connect-type "hotplug"
    '';
  };

  # Sicherheits-Tools verfügbar machen
  environment.systemPackages = with pkgs; [
    usbguard
    aide
    chkrootkit
    unhide      # Findet versteckte Prozesse/Ports (Rootkit-Erkennung)

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
            <allow_any>auth_self</allow_any>
            <allow_inactive>auth_self</allow_inactive>
            <allow_active>auth_self</allow_active>
          </defaults>
        </action>
      </policyconfig>
    '')
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
    killUnconfinedConfinables = true; # Unkontrollierte Prozesse mit AppArmor-Profil stoppen
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

    # NixOS Konfiguration (Flake-basiert)
    /home/achim/nixos-config CONTENT

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
    !/home/achim/nixos-config/.git
    !/home/achim/nixos-config/result
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
  # ROOTKIT-ERKENNUNG (unhide & chkrootkit)
  # ==========================================

  # unhide - Findet versteckte Prozesse und Ports (Rootkit-Indikator)
  # Scan-Service für versteckte Prozesse
  systemd.services.unhide-check = {
    description = "Unhide Hidden Process Scanner";
    path = [ pkgs.unhide pkgs.procps ];
    serviceConfig = {
      Type = "oneshot";
      # Prüfe auf versteckte Prozesse mit verschiedenen Techniken
      ExecStart = "${pkgs.unhide}/bin/unhide sys procall";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Scan-Service für versteckte TCP/UDP Ports
  systemd.services.unhide-tcp-check = {
    description = "Unhide Hidden TCP/UDP Port Scanner";
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
    description = "Weekly Unhide Process Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Wöchentlicher unhide-tcp Scan (Sonntag 05:15)
  systemd.timers.unhide-tcp-check = {
    description = "Weekly Unhide TCP/UDP Scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:15:00";
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
        # Maximale Dateigröße zum Scannen (100MB)
        MaxFileSize = "100M";
        MaxScanSize = "100M";
        # Echtzeit-Scanning Konfiguration (für clamonacc)
        OnAccessIncludePath = [ "/home" ];
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

  # Log-Verzeichnis für ClamAV erstellen
  systemd.tmpfiles.rules = [
    "d /var/log/clamav 0750 clamav clamav -"
  ];

  # clamonacc Service für Echtzeit-Scanning
  systemd.services.clamonacc = {
    description = "ClamAV On-Access Scanner";
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
    };
  };

  # PAM-Services für FIDO2 aktivieren
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.gdm-password.u2fAuth = true;

  # GNOME Keyring bei Login automatisch entsperren (erstellt "login"-Collection)
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;
}
