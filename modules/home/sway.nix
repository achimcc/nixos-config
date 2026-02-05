# Sway Window Manager Konfiguration
# Alternative Session zu GNOME für Tiling Window Manager Workflow

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SWAY - WAYLAND TILING WINDOW MANAGER
  # ==========================================

  wayland.windowManager.sway = {
    enable = true;

    config = rec {
      # Mod-Key: Super/Windows-Taste
      modifier = "Mod4";

      # Terminal
      terminal = "${pkgs.blackbox-terminal}/bin/blackbox";

      # Application Launcher
      menu = "${pkgs.wofi}/bin/wofi --show drun";

      # Keybindings
      keybindings = lib.mkOptionDefault {
        # Application Launcher
        "${modifier}+d" = "exec ${menu}";

        # Screenshots
        "Print" = ''exec ${pkgs.grim}/bin/grim ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png'';
        "Shift+Print" = ''exec ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png'';

        # Volume Control (PipeWire/PulseAudio)
        "XF86AudioRaiseVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        "XF86AudioLowerVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
        "XF86AudioMute" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        "XF86AudioMicMute" = "exec ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle";

        # Brightness Control
        "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
        "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
      };

      # Startup Programs
      startup = [
        # Status Bar
        { command = "${pkgs.waybar}/bin/waybar"; }
        # Notification Daemon
        { command = "${pkgs.mako}/bin/mako"; }
      ];

      # Window Borders
      window = {
        border = 2;
        titlebar = true;
      };

      # Gaps
      gaps = {
        inner = 5;
        outer = 2;
      };

      # Colors (Sway Default Theme)
      colors = {
        focused = {
          background = "#285577";
          border = "#4c7899";
          childBorder = "#285577";
          indicator = "#2e9ef4";
          text = "#ffffff";
        };
        focusedInactive = {
          background = "#5f676a";
          border = "#333333";
          childBorder = "#5f676a";
          indicator = "#484e50";
          text = "#ffffff";
        };
        unfocused = {
          background = "#222222";
          border = "#333333";
          childBorder = "#222222";
          indicator = "#292d2e";
          text = "#888888";
        };
        urgent = {
          background = "#900000";
          border = "#2f343a";
          childBorder = "#900000";
          indicator = "#900000";
          text = "#ffffff";
        };
      };

      # Output Configuration (handled by kanshi)
      # Outputs are dynamically configured by kanshi service

      # Input Configuration
      input = {
        "*" = {
          xkb_layout = "de";
          xkb_variant = "nodeadkeys";
        };
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
          dwt = "enabled"; # Disable while typing
        };
      };
    };

    # Extra Sway Config (for advanced users)
    extraConfig = ''
      # Screenshots Directory erstellen falls nicht vorhanden
      exec mkdir -p ~/Pictures/Screenshots
    '';
  };

  # ==========================================
  # WAYBAR - STATUS BAR
  # ==========================================

  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;

        modules-left = [ "sway/workspaces" "sway/mode" ];
        modules-center = [ "sway/window" ];
        modules-right = [ "tray" "pulseaudio" "network" "battery" "clock" ];

        # Workspaces
        "sway/workspaces" = {
          disable-scroll = false;
          all-outputs = true;
          format = "{icon}";
          format-icons = {
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "9" = "9";
            urgent = "";
            focused = "";
            default = "";
          };
        };

        # Window Title
        "sway/window" = {
          max-length = 50;
        };

        # System Tray
        tray = {
          spacing = 10;
        };

        # Audio
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "🔇 {volume}%";
          format-icons = {
            headphone = "🎧";
            default = [ "🔈" "🔉" "🔊" ];
          };
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        # Network
        network = {
          format-wifi = "📶 {signalStrength}%";
          format-ethernet = "🖧 {ifname}";
          format-disconnected = "⚠ Disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
        };

        # Battery
        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "🔌 {capacity}%";
          format-plugged = "🔌 {capacity}%";
          format-icons = [ "🪫" "🔋" "🔋" "🔋" "🔋" ];
        };

        # Clock
        clock = {
          format = "🕐 {:%H:%M}";
          format-alt = "📅 {:%Y-%m-%d}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "month";
            on-scroll = 1;
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'><b>{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
        };
      };
    };

    # Waybar Styling
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "Source Code Pro", monospace;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.9);
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 8px;
        color: #cdd6f4;
        background: transparent;
      }

      #workspaces button.focused {
        background: #585b70;
        border-bottom: 2px solid #89b4fa;
      }

      #workspaces button.urgent {
        background: #f38ba8;
        color: #1e1e2e;
      }

      #mode {
        background: #f9e2af;
        color: #1e1e2e;
        padding: 0 10px;
        margin: 0 5px;
      }

      #window {
        color: #cdd6f4;
        font-weight: bold;
      }

      #tray,
      #pulseaudio,
      #network,
      #battery,
      #clock {
        padding: 0 10px;
        margin: 0 2px;
        background: rgba(69, 71, 90, 0.8);
        border-radius: 5px;
      }

      #pulseaudio {
        color: #89dceb;
      }

      #network {
        color: #a6e3a1;
      }

      #battery {
        color: #f9e2af;
      }

      #battery.charging {
        color: #a6e3a1;
      }

      #battery.warning:not(.charging) {
        color: #fab387;
      }

      #battery.critical:not(.charging) {
        color: #f38ba8;
        animation: blink 1s linear infinite;
      }

      @keyframes blink {
        to {
          background: #f38ba8;
          color: #1e1e2e;
        }
      }

      #clock {
        color: #b4befe;
      }
    '';
  };

  # ==========================================
  # MAKO - NOTIFICATION DAEMON
  # ==========================================

  services.mako = {
    enable = true;

    settings = {
      # Position
      anchor = "top-right";

      # Timeout
      default-timeout = 5000; # 5 Sekunden

      # Styling
      width = 350;
      height = 100;
      margin = "10";
      padding = "10";
      border-size = 2;
      border-radius = 5;

      # Colors (Dark Theme)
      background-color = "#2e3440";
      text-color = "#d8dee9";
      border-color = "#88c0d0";

      # Critical Notifications (permanent)
      "[urgency=high]" = {
        border-color = "#bf616a";
        default-timeout = 0;
      };
    };
  };

  # ==========================================
  # KANSHI - MONITOR MANAGEMENT
  # ==========================================

  services.kanshi = {
    enable = true;

    systemdTarget = "graphical-session.target";

    settings = [
      # Fallback-Profil: Alle Displays aktivieren
      {
        profile = {
          name = "default";
          outputs = [
            {
              criteria = "*";
              status = "enable";
            }
          ];
        };
      }
    ];
  };

  # ==========================================
  # ZUSÄTZLICHE PAKETE FÜR SWAY
  # ==========================================

  home.packages = with pkgs; [
    # Application Launcher
    wofi

    # Brightness Control
    brightnessctl

    # Audio Control GUI
    pavucontrol

    # Network Manager Applet
    networkmanagerapplet

    # Screenshot Tools (bereits in home.nix, hier zur Dokumentation)
    # grim
    # slurp
    # swappy
  ];
}
