# Kernel & System Hardening
# Zusätzliche Sicherheitsmaßnahmen auf Kernel-Ebene

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # KERNEL HARDENING
  # ==========================================

  boot.kernel.sysctl = {
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

    # TCP Timestamps (Privacy vs. Performance - optional deaktivieren)
    # "net.ipv4.tcp_timestamps" = 0;
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

  # Audit Framework aktivieren (optional - für Logging)
  # security.auditd.enable = true;
}
