# Tastaturlayout automatisch zur angeschlossenen Tastatur umschalten
#
# Zwei Tastaturen, zwei Beschriftungen: die NuPhy Air75 V3 ist US-bedruckt und
# will us-umlaut (Umlaute auf der linken Option-Taste, siehe modules/desktop.nix),
# die eingebaute ThinkPad-Tastatur ist deutsch bedruckt und will de.
#
# GNOME kann Layouts nicht pro Gerät zuordnen — Mutter kennt nur eine aktive
# Eingabequelle für die ganze Sitzung. Also beobachtet ein kleiner Dienst, ob die
# Air75 da ist, und setzt die aktive Quelle entsprechend.
#
# Er reagiert ausschließlich auf An- und Abstecken. Wer zwischendurch von Hand
# umschaltet (Super+Space), behält seine Wahl bis zum nächsten Steckvorgang.

{ config, lib, pkgs, ... }:

let
  # Woran die externe Tastatur erkannt wird. Bewusst der Gerätename und nicht die
  # Bluetooth-MAC: die Air75 kann auch per Kabel oder 2,4-GHz-Dongle angeschlossen
  # sein, dann gibt es gar kein Bluetooth-Gerät. Sie meldet sich in beiden Fällen
  # als "Air75 V3-1 Keyboard" (plus ein zweites Gerät "Air75 V3-1 Mouse").
  tastaturKennung = "Air75";

  # dconf-Pfad statt gsettings: dconf braucht kein GSettings-Schema im
  # XDG_DATA_DIRS, das im systemd-Nutzerkontext nicht zuverlässig gesetzt ist.
  dconfPfad = "/org/gnome/desktop/input-sources/current";

  automatik = pkgs.writeShellApplication {
    name = "tastaturlayout-automatik";
    runtimeInputs = with pkgs; [ dconf systemd gnugrep coreutils ];
    text = ''
      # Index in der Quellenliste aus modules/home/gnome-settings.nix:
      #   0 = us-umlaut (Air75), 1 = de (ThinkPad)
      anwenden() {
        local ziel ist
        if grep -q 'Name="${tastaturKennung}' /proc/bus/input/devices; then
          ziel=0
        else
          ziel=1
        fi

        # dconf liefert "uint32 0" — oder gar nichts, solange der Schlüssel auf
        # dem Vorgabewert steht. Dann zählt die Vorgabe, also 0.
        ist="$(dconf read ${dconfPfad} || true)"
        ist="''${ist##* }"
        [ -n "$ist" ] || ist=0

        if [ "$ist" != "$ziel" ]; then
          dconf write ${dconfPfad} "uint32 $ziel"
          echo "Eingabequelle $ist -> $ziel (${tastaturKennung} $( [ "$ziel" = 0 ] && echo angeschlossen || echo getrennt ))"
        fi
      }

      # Beim Start einmal den Ist-Zustand herstellen — sonst stimmt das Layout
      # erst nach dem naechsten Steckvorgang.
      anwenden

      # --udev (nicht --kernel) heisst: nach der Regelverarbeitung, das Geraet ist
      # dann in /proc/bus/input/devices schon aufgetaucht bzw. verschwunden.
      udevadm monitor --udev --subsystem-match=input | while read -r zeile; do
        case "$zeile" in
          *" add "*|*" remove "*)
            # Die Air75 bringt zwei Eingabegeraete mit, die nicht gleichzeitig
            # erscheinen. Ohne die kurze Pause sieht der erste Durchlauf nur die
            # Maus und schaltet einmal falsch, bevor die Tastatur nachkommt.
            sleep 0.5
            anwenden
            ;;
        esac
      done
    '';
  };
in
{
  systemd.user.services.tastaturlayout-automatik = {
    Unit = {
      Description = "Tastaturlayout zur angeschlossenen Tastatur umschalten";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = lib.getExe automatik;
      # Stirbt der udev-Monitor (Neustart von systemd-udevd), waere das Layout
      # stumm eingefroren — deshalb neu starten statt stillschweigend aufgeben.
      Restart = "always";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Zum Nachsehen und Nachhelfen von Hand
  home.packages = [ automatik ];
}
