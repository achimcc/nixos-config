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

      # Festplatten
      DISK_IOSCHED = [ "mq-deadline" ];

      # WiFi Power Save
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # USB Autosuspend
      USB_AUTOSUSPEND = 1;

      # Akku-Ladeschwellen (falls unterstützt)
      # Schont den Akku durch begrenztes Laden
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Power-profiles-daemon deaktivieren (kollidiert mit TLP)
  services.power-profiles-daemon.enable = false;

  # ==========================================
  # THERMALD - Temperaturmanagement
  # ==========================================

  services.thermald.enable = true;

  # ==========================================
  # WEITERE OPTIMIERUNGEN
  # ==========================================

  # Laptop-Deckel schließen -> Suspend
  services.logind = {
    lidSwitch = "suspend";
    lidSwitchExternalPower = "lock"; # Am Netzteil nur sperren
  };

  # Powertop Auto-Tune (optional, zusätzliche Optimierungen)
  powerManagement.powertop.enable = true;
}
