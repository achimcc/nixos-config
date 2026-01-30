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

    # WirePlumber Bluetooth-Konfiguration
    wireplumber.extraConfig."bluetooth" = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];
      };
      "monitor.bluez.rules" = [
        {
          matches = [
            { "device.name" = "~bluez_card.*"; }
          ];
          actions.update-props = {
            "bluez5.auto-connect" = [ "a2dp_sink" "a2dp_source" "hfp_hf" "hsp_hs" ];
            "bluez5.hw-volume" = [ "a2dp_sink" "hfp_hf" "hsp_hs" ];
          };
        }
        {
          matches = [
            { "node.name" = "~bluez_output.*"; }
            { "node.name" = "~bluez_input.*"; }
          ];
          actions.update-props = {
            "session.suspend-timeout-seconds" = 0;
          };
        }
      ];
    };
  };
}
