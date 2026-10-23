"""Virtuelle Monitore in der GNOME-Sitzung, solange dieser Prozess lebt.

Mutter legt einen virtuellen Monitor an, sobald jemand ueber
org.gnome.Mutter.ScreenCast `RecordVirtual` aufruft UND den PipeWire-Strom
abnimmt; die Groesse kommt aus der Aushandlung des Stroms. Abgenommen wird
hier in ein `fakesink` - das Bild holt sich WayVR ueber das Portal selbst.
Endet der Prozess, schliesst Mutter die Sitzungen und die Monitore sind weg.

Aufruf: vr-monitore ANZAHL BREITExHOEHE
        vr-monitore --pruefen     (legt nichts an: Schnittstelle und Plugin da?)

Skalierung (2026-10-17): Fuer die Monitorgruppe MIT den virtuellen Monitoren
hat Mutter keine gespeicherte Konfiguration (monitors.xml kennt nur die echten),
also baut es eine neue und waehlt die Skala jedes Bildschirms nach seiner
Pixeldichte - fuer das 14"-Panel mit 1920x1200 sind das 1,25 statt der
eingestellten 1. Gemessen: Laptop-Bildschirm sprang auf 1,25, XWayland auf
192 DPI, wezterm zeichnete die Reiterleiste eine DPI-Stufe hinterher.
Deshalb merkt sich dieses Skript die Lage und Skala der echten Bildschirme,
bevor es die virtuellen anlegt, und setzt sie danach wieder so
(ApplyMonitorsConfig, voruebergehend); die virtuellen kommen rechts daneben.

Leerlauf (2026-10-17 gemessen, viermal): Wer die Brille traegt, tippt nicht am
Laptop. Nach idle-delay (300 s) blendet GNOME ab, und beim Abblenden sperrt
die Shell den Fernzugriff - Mutter schliesst dabei JEDE Aufnahme- und
Fernzugriffssitzung: die virtuellen Monitore verschwinden ("Removed virtual
monitor"), WayVRs Portal-Aufnahme bricht, Xwaylands Eingabekanal (EIS) auch.
Deshalb haelt dieses Skript bei gnome-session einen Inhibitor gegen den
Leerlauf (Flag 8), solange es laeuft; er faellt mit der D-Bus-Verbindung.
"""

import os
import signal
import sys

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gio, GLib, Gst  # noqa: E402

NAME = "org.gnome.Mutter.ScreenCast"
PFAD = "/org/gnome/Mutter/ScreenCast"
ANZEIGE = "org.gnome.Mutter.DisplayConfig"
ANZEIGE_PFAD = "/org/gnome/Mutter/DisplayConfig"
ZUSTAND_TYP = "(ua((ssss)a(siiddada{sv})a{sv})a(iiduba(ssss)a{sv})a{sv})"
VORUEBERGEHEND = 1  # ApplyMonitorsConfig: nicht in monitors.xml schreiben
FRIST_S = 15


def marke():
    return os.path.join(os.environ["XDG_RUNTIME_DIR"], "vr-monitore.bereit")


def ruf(bus, pfad, schnittstelle, methode, argumente, antwort, name=NAME):
    typ = GLib.VariantType(antwort) if antwort else None
    return bus.call_sync(
        name, pfad, schnittstelle, methode, argumente, typ,
        Gio.DBusCallFlags.NONE, -1, None,
    )


def anzeige_zustand(bus):
    """GetCurrentState: (Serial, Monitore, logische Monitore, Eigenschaften)."""
    return ruf(
        bus, ANZEIGE_PFAD, ANZEIGE, "GetCurrentState", None, ZUSTAND_TYP,
        name=ANZEIGE,
    ).unpack()


def lage_der_bildschirme(zustand):
    """Anschluss -> (x, y, Skala, Drehung, primaer) je logischem Monitor."""
    lage = {}
    for x, y, skala, drehung, primaer, monitore, _ in zustand[2]:
        for anschluss, *_ in monitore:
            lage[anschluss] = (x, y, skala, drehung, primaer)
    return lage


def aktuelle_modi(zustand):
    """Anschluss -> (Modus-Kennung, Breite, Hoehe) des gerade aktiven Modus."""
    modi = {}
    for (anschluss, *_), liste, _ in zustand[1]:
        for kennung, breite, hoehe, *_, eigenschaften in liste:
            if eigenschaften.get("is-current"):
                modi[anschluss] = (kennung, breite, hoehe)
    return modi


def lage_wiederherstellen(vorher, zustand):
    """Konfiguration fuer ApplyMonitorsConfig, falls Mutter die Skala eines
    vorher vorhandenen Bildschirms veraendert hat; sonst None.

    Die vorher vorhandenen Bildschirme bekommen Lage und Skala von `vorher`
    zurueck, alle neuen (die virtuellen) reihen sich rechts daneben auf.
    """
    nachher = lage_der_bildschirme(zustand)
    modi = aktuelle_modi(zustand)
    alt = {a: lage for a, lage in vorher.items() if a in nachher}
    if all(nachher[a][2] == lage[2] for a, lage in alt.items()):
        return None

    logische = []
    rechter_rand = 0
    for anschluss, (x, y, skala, drehung, primaer) in alt.items():
        kennung, breite, _ = modi[anschluss]
        logische.append((x, y, skala, drehung, primaer, [(anschluss, kennung, {})]))
        rechter_rand = max(rechter_rand, x + round(breite / skala))
    for anschluss in nachher:
        if anschluss in alt:
            continue
        kennung, breite, _ = modi[anschluss]
        skala = nachher[anschluss][2]
        logische.append((rechter_rand, 0, skala, 0, False, [(anschluss, kennung, {})]))
        rechter_rand += round(breite / skala)
    return logische


def skala_halten(bus, vorher):
    zustand = anzeige_zustand(bus)
    logische = lage_wiederherstellen(vorher, zustand)
    if logische is None:
        return
    ruf(
        bus, ANZEIGE_PFAD, ANZEIGE, "ApplyMonitorsConfig",
        GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (zustand[0], VORUEBERGEHEND, logische, {})),
        None, name=ANZEIGE,
    )
    print("vr-monitore: Skala der echten Bildschirme wiederhergestellt", flush=True)


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
            try:
                skala_halten(bus, vorher)
            except GLib.Error as fehler:
                # Nur die Skala, nicht die Monitore: weiter ohne Korrektur.
                print(f"vr-monitore: Skala nicht wiederhergestellt: {fehler}", file=sys.stderr)
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

    vorher = lage_der_bildschirme(anzeige_zustand(bus))

    # Leerlauf-Inhibitor (siehe Kopf): Flag 8 = "Sitzung nicht als untaetig
    # werten". Scheitert er, laufen die Monitore trotzdem - nur bis zum
    # naechsten Abblenden, und das steht dann im Journal.
    try:
        ruf(
            bus, "/org/gnome/SessionManager", "org.gnome.SessionManager", "Inhibit",
            GLib.Variant("(susu)", ("vr-monitore", 0, "VR-Sitzung: virtuelle Monitore", 8)),
            "(u)", name="org.gnome.SessionManager",
        )
    except GLib.Error as fehler:
        print(f"vr-monitore: kein Leerlauf-Inhibitor: {fehler}", file=sys.stderr)

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
