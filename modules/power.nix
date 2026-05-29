# Power Management für Laptop
# TLP für Akku-Optimierung, thermald für Temperatur

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # TLP - Akku-Optimierung
  # ==========================================

  services.tlp = {
    enable = true;
    settings = {
      # CPU Governor
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # CPU Turbo
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # Energieprofil
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # Platform Profile (ACPI)
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "balanced";

      # Festplatten
      DISK_IOSCHED = [ "mq-deadline" ];

      # WiFi Power Save
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # USB Autosuspend
      USB_AUTOSUSPEND = 1;

      # SanDisk Portable SSD von Autosuspend ausschließen (Performance)
      USB_EXCLUDE_BTUSB = 0;
      USB_DENYLIST = "0781:55b0";

      # Akku-Ladeschwellen (falls unterstützt)
      # Schont den Akku durch begrenztes Laden
      START_CHARGE_THRESH_BAT0 = 50;  # Laden startet unter 50%
      STOP_CHARGE_THRESH_BAT0 = 90;   # Laden stoppt bei 90%
    };
  };

  # Power-profiles-daemon deaktivieren (kollidiert mit TLP)
  services.power-profiles-daemon.enable = false;

  # ==========================================
  # THERMALD - Temperaturmanagement
  # ==========================================

  # DEAKTIVIERT: ThinkPad T14 Gen 5 (Intel Lunar Lake) wird von thermald nicht unterstützt
  # Fehler: "dytc_lapmode present: Thermald can't run on this platform"
  # Temperatur-Management läuft über TLP + Kernel-Treiber
  services.thermald.enable = false;

  # ==========================================
  # SPEICHER-RESILIENZ (gegen Swap-Thrash-Freeze)
  # ==========================================
  # Problem (analysiert 2026-05-25): Ein leckender Librewolf-Tab wuchs auf ~26 GB
  # RSS, füllte RAM + die komplette 33-GB-Disk-Swap → System erstarrte 40 min im
  # Swap-Thrash, bis der Kernel-OOM den Tab killte. Symptom: 1080p-Video ruckelt
  # "nach ca. 30 min" (= sobald RAM voll ist; betrifft mpv UND vlc, da systemweit).
  #
  # Zwei Hebel:
  # 1) zram: komprimierter RAM-Swap (zstd) mit hoher Prio. Speicherdruck trifft
  #    zuerst schnelles RAM statt NVMe → kein minutenlanges Einfrieren mehr.
  #    Die 33-GB-LUKS-Disk-Swap (hardware-configuration.nix) bleibt unangetastet
  #    für Hibernate/Resume (niedrigere Prio, wird erst nach zram genutzt).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;  # zram-Gerätegröße = 50 % RAM (~15 GB), komprimiert weniger
  };

  # 2) systemd-oomd auf die user.slice ausweiten. Per NixOS-Default überwacht oomd
  #    nur Root-/System-Slices — den Browser (user@1000.service → app.slice) sah
  #    niemand, daher zog erst der Kernel-OOM nach 40 min Totalstall. Mit
  #    enableUserSlices killt oomd das leckende cgroup früh bei hohem Memory-Pressure.
  systemd.oomd = {
    enable = true;            # NixOS-Default, explizit zur Klarheit
    enableUserSlices = true;  # user.slice überwachen → Leak wird früh gekillt
  };

  # ==========================================
  # WEITERE OPTIMIERUNGEN
  # ==========================================

  # Laptop-Deckel schließen -> Suspend
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "lock"; # Am Netzteil nur sperren
  };

  # Powertop Auto-Tune (optional, zusätzliche Optimierungen)
  powerManagement.powertop.enable = true;

  # ==========================================
  # SUSPEND WAKEUP-QUELLEN DEAKTIVIEREN
  # ==========================================
  # Problem: XHCI (USB) und Thunderbolt wecken den Laptop im s2idle-Suspend
  # → Häufige Micro-Wakeups → Akku leer über Nacht
  # LID und SLPB (Sleep Button) bleiben aktiv für normales Aufwachen
  systemd.services.disable-wakeup-sources = {
    description = "Disable spurious ACPI wakeup sources for s2idle";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Deaktiviere Wakeup-Quellen die spurious Wakeups im s2idle verursachen
      for dev in XHCI TXHC TDM0 TDM1 TRP0 TRP2 RP01 RP09 RP10; do
        if grep -q "$dev.*enabled" /proc/acpi/wakeup 2>/dev/null; then
          echo "$dev" > /proc/acpi/wakeup
          echo "Wakeup-Quelle $dev deaktiviert"
        fi
      done
      echo "Aktive Wakeup-Quellen:"
      grep enabled /proc/acpi/wakeup
    '';
  };
}
