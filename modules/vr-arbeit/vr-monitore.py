"""Virtuelle Monitore in der GNOME-Sitzung, solange dieser Prozess lebt.

Mutter legt einen virtuellen Monitor an, sobald jemand ueber
org.gnome.Mutter.ScreenCast `RecordVirtual` aufruft UND den PipeWire-Strom
abnimmt; die Groesse kommt aus der Aushandlung des Stroms. Abgenommen wird
hier in ein `fakesink` - das Bild holt sich WayVR ueber das Portal selbst.
Endet der Prozess, schliesst Mutter die Sitzungen und die Monitore sind weg.

Aufruf: vr-monitore ANZAHL BREITExHOEHE
        vr-monitore --pruefen     (legt nichts an: Schnittstelle und Plugin da?)
"""

import os
import signal
import sys

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gio, GLib, Gst  # noqa: E402

NAME = "org.gnome.Mutter.ScreenCast"
PFAD = "/org/gnome/Mutter/ScreenCast"
FRIST_S = 15


def marke():
    return os.path.join(os.environ["XDG_RUNTIME_DIR"], "vr-monitore.bereit")


def ruf(bus, pfad, schnittstelle, methode, argumente, antwort):
    typ = GLib.VariantType(antwort) if antwort else None
    return bus.call_sync(
        NAME, pfad, schnittstelle, methode, argumente, typ,
        Gio.DBusCallFlags.NONE, -1, None,
    )


def pruefen(bus):
    version = ruf(
        bus, PFAD, "org.freedesktop.DBus.Properties", "Get",
        GLib.Variant("(ss)", (NAME, "Version")), "(v)",
    ).unpack()[0]
    plugin = Gst.ElementFactory.find("pipewiresrc") is not None
    print(f"Mutter ScreenCast Version {version}, pipewiresrc: {plugin}")
    return 0 if plugin and version >= 3 else 1


def main():
    Gst.init(None)
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    if sys.argv[1:] == ["--pruefen"]:
        return pruefen(bus)
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    anzahl = int(sys.argv[1])
    breite, hoehe = (int(x) for x in sys.argv[2].split("x"))

    if Gst.ElementFactory.find("pipewiresrc") is None:
        print("vr-monitore: GStreamer kennt pipewiresrc nicht", file=sys.stderr)
        return 1

    schleife = GLib.MainLoop()
    leitungen = []
    ergebnis = {"code": 0}

    def ende(code):
        ergebnis["code"] = code
        schleife.quit()
        return GLib.SOURCE_REMOVE

    def strom_da(_bus, _absender, _pfad, _schnittstelle, _signal, werte):
        (knoten,) = werte.unpack()
        leitung = Gst.parse_launch(
            f"pipewiresrc path={knoten} ! "
            f"video/x-raw,max-framerate=60/1,width={breite},height={hoehe} ! "
            "fakesink sync=false"
        )
        leitung.set_state(Gst.State.PLAYING)
        leitungen.append(leitung)
        if len(leitungen) == anzahl:
            with open(marke(), "w") as datei:
                datei.write(f"{anzahl} {breite}x{hoehe}\n")
            print(f"vr-monitore: {anzahl} Monitore {breite}x{hoehe}", flush=True)

    def geschlossen(*_):
        print("vr-monitore: Mutter hat die Sitzung geschlossen", file=sys.stderr)
        ende(1)

    def frist():
        if len(leitungen) < anzahl:
            print(
                f"vr-monitore: nach {FRIST_S} s nur {len(leitungen)} von "
                f"{anzahl} Stroemen",
                file=sys.stderr,
            )
            ende(1)
        return GLib.SOURCE_REMOVE

    for _ in range(anzahl):
        (sitzung,) = ruf(
            bus, PFAD, NAME, "CreateSession",
            GLib.Variant("(a{sv})", ({},)), "(o)",
        ).unpack()
        (strom,) = ruf(
            bus, sitzung, NAME + ".Session", "RecordVirtual",
            GLib.Variant("(a{sv})", ({"is-platform": GLib.Variant("b", True)},)),
            "(o)",
        ).unpack()
        bus.signal_subscribe(
            NAME, NAME + ".Stream", "PipeWireStreamAdded", strom, None,
            Gio.DBusSignalFlags.NONE, strom_da,
        )
        bus.signal_subscribe(
            NAME, NAME + ".Session", "Closed", sitzung, None,
            Gio.DBusSignalFlags.NONE, geschlossen,
        )
        ruf(bus, sitzung, NAME + ".Session", "Start", None, None)

    GLib.timeout_add_seconds(FRIST_S, frist)
    for nummer in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, nummer, ende, 0)

    schleife.run()

    for leitung in leitungen:
        leitung.set_state(Gst.State.NULL)
    try:
        os.unlink(marke())
    except FileNotFoundError:
        pass
    return ergebnis["code"]


if __name__ == "__main__":
    sys.exit(main())
