# Moonfin — Jellyfin-Client für den eigenen Jellyfin
# (jellyfin.rusty-vault.de). Paket: pkgs/moonfin (Release-Bau von upstream, Bibliotheken aus
# nixpkgs, damit die Hardware-Dekodierung über /run/opengl-driver läuft).
#
# Server-Vorgabe: Der Start trägt den Server in Moonfins Serverliste ein, wenn
# er dort fehlt (Skript `serverEintragen` in pkgs/moonfin). Die Server-ID holt
# es beim ersten Start von /System/Info/Public — ohne VPN ist das Netz zu
# (Kill-Switch), dann bleibt die Liste leer bis zum nächsten Start mit Netz.
# Angemeldet wird einmalig in der App; das Token legt Moonfin selbst ab.
#
# Nicht deklariert: die übrigen App-Einstellungen. Sie liegen in derselben
# shared_preferences.json, die Moonfin bei jeder Änderung neu schreibt; eine
# Datei aus dem Store wäre schreibgeschützt und bräche die App.

{ pkgs, ... }:

{
  home.packages = [
    (pkgs.moonfin.override { serverUrl = "https://jellyfin.rusty-vault.de"; })
  ];
}
