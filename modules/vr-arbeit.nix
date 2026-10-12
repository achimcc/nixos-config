# Arbeiten an virtuellen Monitoren in der Meta Quest 3 - in der GNOME-Sitzung
#
# WiVRn streamt eine OpenXR-Sitzung in die Brille, WayVR zeigt darin die
# Monitore des Desktops. Die virtuellen Monitore legt Mutter selbst an
# (org.gnome.Mutter.ScreenCast, `RecordVirtual`) - solange `vr-monitore` lebt,
# stehen sie wie angesteckte Bildschirme in Einstellungen > Bildschirme.
#
# Der Weg zur Brille ist das USB-Kabel (`adb reverse`), nicht das WLAN: Der
# Strom laeuft dann ueber Loopback, die Firewall bleibt zu, und der Kill-Switch
# ist nicht beruehrt. Die USBGuard-Regel fuer die Quest steht in security.nix.
#
# Bedienung: `vr-arbeit an [anzahl] [BREITExHOEHE]`, `vr-arbeit aus`,
# `vr-arbeit status`. Beim ersten Mal vorher `wivrnctl pair` und die PIN in der
# Brille eingeben; WayVR fragt beim ersten Start ueber den GNOME-Dialog, welche
# Monitore es zeigen darf.
#
# GEMESSEN (2026-10-12, laufende Sitzung): Mutter ScreenCast Version 4, das
# Portal meldet AvailableSourceTypes = 7 (Monitor, Fenster, virtuell).
# NICHT GEMESSEN (vor dem ersten Rebuild): ob WiVRn 26.6.2 gegen dieses nixpkgs
# baut, ob `vr-monitore` die Monitore wirklich anlegt (es haette die laufende
# Sitzung umgeraeumt), ob WayVR sie im Portal-Dialog anbietet, ob die Arc-iGPU
# unter Vulkan-Dauerlast stabil bleibt (desktop.nix fuehrt drei GPU-Haenger),
# und der `am start`-Aufruf.

{ config, lib, pkgs, ... }:

let
  wivrnPort = 9757;

  # Typelibs und GStreamer-Plugins kommen ueber den Wrapper: Ein Nutzerdienst
  # erbt die Sitzungsvariablen der GNOME-Shell nicht verlaesslich.
  vr-monitore = pkgs.writers.writePython3Bin "vr-monitore"
    {
      libraries = [ pkgs.python3Packages.pygobject3 ];
      flakeIgnore = [ "E501" ];
      makeWrapperArgs = [
        "--prefix"
        "GI_TYPELIB_PATH"
        ":"
        (lib.makeSearchPath "lib/girepository-1.0" [
          pkgs.glib.out
          pkgs.gobject-introspection
          pkgs.gst_all_1.gstreamer.out
        ])
        "--prefix"
        "GST_PLUGIN_SYSTEM_PATH_1_0"
        ":"
        (lib.makeSearchPath "lib/gstreamer-1.0" [
          pkgs.gst_all_1.gstreamer.out
          pkgs.gst_all_1.gst-plugins-base
          pkgs.pipewire
        ])
      ];
    }
    (builtins.readFile ./vr-arbeit/vr-monitore.py);

  vr-arbeit = pkgs.writeShellApplication {
    name = "vr-arbeit";
    runtimeInputs = with pkgs; [ android-tools systemd iproute2 coreutils gawk gnused ];
    text = ''
      port=${toString wivrnPort}
      marke="''${XDG_RUNTIME_DIR:?}/vr-monitore.bereit"

      braucht_gnome() {
        case "''${XDG_CURRENT_DESKTOP:-}" in
          *GNOME*) ;;
          *)
            echo "vr-arbeit: nur in der GNOME-Sitzung - die virtuellen Monitore legt Mutter an." >&2
            exit 1
            ;;
        esac
      }

      # Wartet auf den ZUSTAND, nicht auf einen Exit-Code: $1 = ss-Zustand,
      # $2 = Grenze in Sekunden.
      warte_auf_port() {
        local i=0
        while [ "$i" -lt "$2" ]; do
          if [ -n "$(ss -Htn state "$1" "( sport = :$port )")" ]; then
            return 0
          fi
          sleep 1
          i=$((i + 1))
        done
        return 1
      }

      monitore_an() {
        local soll="$1 $2" i=0
        if [ -e "$marke" ] && [ "$(cat "$marke")" = "$soll" ]; then
          return 0
        fi
        systemctl --user stop vr-monitore.service 2>/dev/null || true
        systemd-run --user --quiet --collect --unit=vr-monitore \
          ${vr-monitore}/bin/vr-monitore "$1" "$2"
        # Die Marke schreibt vr-monitore erst, wenn Mutter JEDEN Strom
        # gemeldet hat - ein laufender Prozess allein belegt keinen Monitor.
        while [ "$i" -lt 20 ]; do
          if [ -e "$marke" ]; then
            return 0
          fi
          sleep 1
          i=$((i + 1))
        done
        echo "vr-arbeit: keine virtuellen Monitore nach 20 s - journalctl --user -u vr-monitore" >&2
        exit 1
      }

      an() {
        local anzahl="''${1:-2}" aufloesung="''${2:-2560x1440}" geraete paket
        braucht_gnome
        monitore_an "$anzahl" "$aufloesung"

        systemctl --user start wivrn.service
        if ! warte_auf_port listening 15; then
          echo "vr-arbeit: WiVRn lauscht nach 15 s nicht auf $port - journalctl --user -u wivrn" >&2
          exit 1
        fi

        geraete=$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)
        if [ "$geraete" -ne 1 ]; then
          echo "vr-arbeit: $geraete Geraete in adb, gebraucht wird genau eines." >&2
          echo "  Kabel? USBGuard (usbguard list-devices)? Debug-Freigabe in der Brille?" >&2
          exit 1
        fi
        adb reverse "tcp:$port" "tcp:$port" >/dev/null

        # Store- und GitHub-Fassung des Clients heissen verschieden.
        paket=$(adb shell pm list packages org.meumeu.wivrn | tr -d '\r' | sed -n '1s/^package://p')
        if [ -z "$paket" ]; then
          echo "vr-arbeit: kein WiVRn-Client auf der Brille (org.meumeu.wivrn*)." >&2
          exit 1
        fi
        adb shell am start -a android.intent.action.VIEW -d "wivrn+tcp://localhost" "$paket" >/dev/null

        if warte_auf_port established 30; then
          echo "vr-arbeit: Brille verbunden, $anzahl virtuelle Monitore ($aufloesung)."
        else
          echo "vr-arbeit: nach 30 s keine Verbindung auf $port." >&2
          echo "  Erstes Mal? 'wivrnctl pair' und die PIN in der Brille eingeben." >&2
          exit 1
        fi
      }

      aus() {
        systemctl --user stop wivrn.service
        systemctl --user stop vr-monitore.service 2>/dev/null || true
        adb reverse --remove "tcp:$port" >/dev/null 2>&1 || true
        echo "vr-arbeit: aus."
      }

      status() {
        echo "wivrn.service: $(systemctl --user is-active wivrn.service || true)"
        echo "Verbindungen auf $port: $(ss -Htn state established "( sport = :$port )" | wc -l)"
        if [ -e "$marke" ]; then
          echo "virtuelle Monitore: $(cat "$marke")"
        else
          echo "virtuelle Monitore: keine"
        fi
      }

      case "''${1:-}" in
        an) shift; an "$@" ;;
        aus) aus ;;
        status) status ;;
        *)
          echo "Aufruf: vr-arbeit an [anzahl] [BREITExHOEHE] | aus | status" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  # ==========================================
  # WIVRN
  # ==========================================

  services.wivrn = {
    enable = true;
    # Auf 26.6.2 festgehalten: pkgs/wivrn/package.nix.
    package = pkgs.wivrn;

    # Kein Dauerlaeufer: `vr-arbeit an` startet den Dienst, `aus` stoppt ihn.
    autoStart = false;

    # Der Strom kommt ueber `adb reverse` auf Loopback an. Der Schalter
    # oeffnete 9757 fuer jede Quelle in jedem Netz.
    openFirewall = false;

    # Vorgabe ist `true` und zoege Steam (unfrei) in den PATH des Dienstes.
    steam.enable = false;

    # Ohne Avahi stirbt der Server sonst mit "Cannot create avahi client:
    # Daemon not running" (auf vr-01 gemessen, 2026-10-05).
    extraServerFlags = [ "--no-publish-service" ];

    # WayVR startet mit der Verbindung der Brille und endet mit ihr. Encoder
    # und Bitrate bleiben bei WiVRns Vorgabe, bis sie gemessen sind.
    config = {
      enable = true;
      json.application = [ pkgs.wayvr ];
    };
  };

  # Das WiVRn-Modul schaltet Avahi samt Veroeffentlichung ein. mDNS ist auf
  # diesem Geraet mit Absicht aus (configuration.nix, firewall.nix) - die Brille
  # findet den Server ueber `adb reverse`, nicht ueber das Netz.
  services.avahi.enable = lib.mkForce false;

  # Das Modul haertet den Nutzerdienst mit ProtectSystem=strict; damit ist im
  # Namensraum des Dienstes auch das Heim schreibgeschuetzt ("cannot create
  # directories: Read-only file system [~/.config/wivrn]", auf vr-01 gemessen).
  # %h fuer Konfiguration und Kopplungen, %t fuer den IPC-Socket, an dem WayVR
  # haengt.
  systemd.user.services.wivrn.serviceConfig.ReadWritePaths = [ "%h" "%t" ];

  # ==========================================
  # WERKZEUGE
  # ==========================================

  # KEIN uinput fuer WayVR: Getippt wird auf der Tastatur des Laptops, der
  # Zeiger wandert in GNOME von selbst ueber die virtuellen Monitore. Ein
  # Nutzerprozess mit Schreibrecht auf /dev/uinput koennte Eingaben faelschen.
  environment.systemPackages = [
    vr-arbeit
    vr-monitore
    pkgs.android-tools # adb fuer den Kabelweg
  ];
}
