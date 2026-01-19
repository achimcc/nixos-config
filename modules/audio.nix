# Audio Konfiguration
# Pipewire mit PulseAudio-Kompatibilität

{ config, lib, pkgs, ... }:

{
  # Realtime-Scheduling für Audio
  security.rtkit.enable = true;

  # Pipewire als Audio-System
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true; # PulseAudio-Kompatibilität
  };
}
