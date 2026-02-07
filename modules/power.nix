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
  # WEITERE OPTIMIERUNGEN
  # ==========================================

  # Laptop-Deckel schließen -> Suspend
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "lock"; # Am Netzteil nur sperren
  };

  # Powertop Auto-Tune (optional, zusätzliche Optimierungen)
  powerManagement.powertop.enable = true;
}
