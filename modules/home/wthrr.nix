# wthrr (the weathercrab) — Wetter im Terminal.
# https://github.com/ttytm/wthrr-the-weathercrab
#
# `wthrr` ohne Argument zeigt das Wetter am Standardort unten; `wthrr <ort>`
# einen anderen, `wthrr -f d,w` zusätzlich Tages- und Wochenvorhersage.
#
# ZWEI DATEIEN, und die zweite ist der Grund für diese Datei:
#
#   1. `wthrr.ron` — Ort, Sprache, Einheiten. Liegt als Symlink im Store und
#      ist damit schreibgeschützt: `wthrr -s` (Einstellung speichern) scheitert
#      absichtlich. Geändert wird hier.
#
#   2. `locales/de_DE.json` — die deutschen Texte. wthrr bringt keine
#      Übersetzungen mit: fehlt diese Datei, schickt es bei JEDEM Aufruf jeden
#      Text einzeln an translate.googleapis.com (src/modules/localization.rs,
#      `translate_all`) und legt das Ergebnis nur bei `-s` ab — was wegen (1)
#      nie gelingt. Die Datei hier erspart den Google-Kontakt und die Wartezeit.
#      Fehlt ein Feld, nimmt wthrr dafür den englischen Text.
#
# Netz: Ortssuche über nominatim.openstreetmap.org, Wetterdaten von
# api.open-meteo.com. Ohne VPN ist das Netz zu (Kill-Switch) — dann meldet
# wthrr einen Verbindungsfehler, und das ist kein Fehler dieser Datei.
#
# Die Symbole brauchen eine Nerd Font im Terminal (wezterm: Hack Nerd Font Mono).

{ pkgs, ... }:

let
  language = "de_DE";

  # Feldnamen wie in `struct Locales` (src/modules/localization.rs).
  locales = {
    greeting = "Hallo. Schön, dass du fragst.";
    search_station = "Du hast keinen Ort angegeben. Soll ich nach einer Wetterstation in deiner Nähe suchen?";
    config = {
      confirm = "Ja, bitte";
      next_time = "Nein, frag mich beim nächsten Mal";
      deny = "Nein, frag mich nicht wieder";
      always_auto = "Immer nach einer Wetterstation suchen";
      save_as_default = "Soll das dein Standard werden?";
      reset_config = "Das löscht die Konfiguration von wthrr. Fortfahren?";
      no_selection = "Nichts ausgewählt oder abgebrochen";
    };
    weather = {
      feels_like = "Gefühlt";
      felt_like = "Gefühlt";
      humidity = "Luftfeuchtigkeit";
      dew_point = "Taupunkt";
      hourly_forecast = "Stündliche Vorhersage";
      daily_overview = "Tagesübersicht";
      weather_code = {
        clear_sky = "Klarer Himmel";
        mostly_clear = "Überwiegend klar";
        partly_cloudy = "Teilweise bewölkt";
        overcast = "Bedeckt";
        fog = "Nebel";
        depositing_rime_fog = "Nebel mit Reifbildung";
        light_drizzle = "Leichter Nieselregen";
        moderate_drizzle = "Mäßiger Nieselregen";
        dense_drizzle = "Dichter Nieselregen";
        light_freezing_drizzle = "Leichter gefrierender Nieselregen";
        dense_freezing_drizzle = "Dichter gefrierender Nieselregen";
        slight_rain = "Leichter Regen";
        moderate_rain = "Mäßiger Regen";
        heavy_rain = "Starker Regen";
        light_freezing_rain = "Leichter gefrierender Regen";
        heavy_freezing_rain = "Starker gefrierender Regen";
        slight_snow_fall = "Leichter Schneefall";
        moderate_snow_fall = "Mäßiger Schneefall";
        heavy_snow_fall = "Starker Schneefall";
        snow_grains = "Schneegriesel";
        slight_rain_showers = "Leichte Regenschauer";
        moderate_rain_showers = "Mäßige Regenschauer";
        violent_rain_showers = "Heftige Regenschauer";
        slight_snow_showers = "Leichte Schneeschauer";
        heavy_snow_showers = "Starke Schneeschauer";
        thunderstorm = "Gewitter";
        thunderstorm_slight_hail = "Gewitter mit leichtem Hagel";
        thunderstorm_heavy_hail = "Gewitter mit starkem Hagel";
      };
    };
  };
in
{
  home.packages = [ pkgs.wthrr ];

  # Postleitzahl im Suchtext: Nominatim liefert dafür genau einen Treffer,
  # „Nordstemmen, Landkreis Hildesheim, Niedersachsen, 31171, Deutschland".
  xdg.configFile."weathercrab/wthrr.ron".text = ''
    (
        address: "31171 Nordstemmen",
        language: "${language}",
        forecast: [day],
        units: (
            temperature: celsius,
            speed: kmh,
            time: military,
            precipitation: probability,
        ),
        gui: (
            border: rounded,
            color: default,
            graph: (
                style: lines(solid),
                rowspan: double,
                time_indicator: true,
            ),
            greeting: true,
        ),
    )
  '';

  xdg.configFile."weathercrab/locales/${language}.json".text = builtins.toJSON locales;
}
