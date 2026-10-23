# Moonfin — Jellyfin-Client (github.com/Moonfin-Client/Moonfin-Core, GPL-2.0,
# Flutter). Steht weder in nixpkgs noch auf Flathub (2026-10-23 geprüft).
# Einbindung und Server-Vorgabe: modules/home/moonfin.nix.
#
# WARUM DAS RELEASE-TARBALL UND KEIN QUELLBAU: Moonfin ist eine Flutter-App mit
# rund zwanzig Plugins und eigenen Paketen unter packages/; ein Quellbau
# braucht einen Flutter-Pubspec-Lock samt Git-Abhängigkeiten. Das Tarball ist
# derselbe Linux-Bau, den upstream als .deb/.rpm/AppImage verteilt.
#
# WAS VOM TARBALL BLEIBT: Upstream legt ~400 Bibliotheken aus Ubuntu 24.04 bei
# (libmpv samt ffmpeg 6, libva, libvulkan, WebKitGTK …). Gemischt mit den
# nixpkgs-Fassungen von GTK und glibc wäre das ein Glücksspiel, und die
# beigelegte libva fände die Treiber unter /run/opengl-driver nicht —
# Hardware-Dekodierung ist auf dieser Maschine Pflicht. Behalten werden nur
# die Teile, die Moonfin selbst baut (Flutter-Engine, App, Plugins, pdfium,
# sqlite); alles andere kommt aus nixpkgs und wird von autoPatchelf verdrahtet.
#
# AUF DIE VERSION GEPINNT. Beim Anheben: neues Tarball, `nix build` des Pakets
# — fordert ein Plugin eine neue Bibliothek an, nennt autoPatchelf sie.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, wrapGAppsHook3
, gtk3
, glib
, pango
, cairo
, harfbuzz
, atk
, gdk-pixbuf
, zlib
, libepoxy
, libsecret
, libarchive
, libGL
, libva
, vulkan-loader
, mpv-unwrapped
, webkitgtk_4_1
, libsoup_3
, SDL2
, libpulseaudio
, alsa-lib
, xdg-utils
, writeShellScript
, curl
, jq
, coreutils
  # Server, den der Start in Moonfins Serverliste einträgt, falls er fehlt
  # (z. B. "https://jellyfin.example.org"); null = keine Vorgabe.
, serverUrl ? null
}:

let
  # Moonfin hält seine Serverliste als JSON-Zeichenkette unter
  # `authentication_store_json` in shared_preferences (lib/auth/store/
  # authentication_store.dart, Format-Version 2), Schlüssel jedes Eintrags ist
  # die Server-ID von Jellyfin. Die ID steht nicht im Repo, sondern wird beim
  # Start von /System/Info/Public geholt — nur wenn der Eintrag fehlt. Ohne
  # Netz (Kill-Switch) startet Moonfin einfach ohne Vorgabe; kein Abbruch.
  # Vorhandene Einträge und Anmeldungen bleiben unberührt.
  serverEintragen = writeShellScript "moonfin-server-eintragen" ''
    set -u
    PATH=${lib.makeBinPath [ coreutils ]}:$PATH
    adresse=${lib.escapeShellArg serverUrl}
    prefs="''${XDG_DATA_HOME:-$HOME/.local/share}/org.moonfin.linux/shared_preferences.json"
    jq=${lib.getExe jq}

    if [ -s "$prefs" ] && "$jq" -e --arg a "$adresse" '
        (.["flutter.authentication_store_json"] // "{}" | fromjson | .servers // {})
        | to_entries | any(.value.address | rtrimstr("/") == ($a | rtrimstr("/")))
      ' "$prefs" >/dev/null 2>&1; then
      exit 0
    fi

    info=$(${lib.getExe curl} -sf --max-time 5 "$adresse/System/Info/Public") || {
      echo "moonfin: $adresse nicht erreichbar, Server nicht vorbelegt" >&2
      exit 0
    }

    mkdir -p "$(dirname "$prefs")"
    [ -s "$prefs" ] || echo '{}' > "$prefs"
    jetzt=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    neu=$("$jq" --arg a "$adresse" --arg t "$jetzt" --argjson info "$info" '
      .["flutter.authentication_store_json"] |= (
        (. // "" | try fromjson catch null) as $s
        | (if $s != null and $s.version == 2 then $s else { version: 2, servers: {} } end)
        | .servers[$info.Id] = {
            name: $info.ServerName, address: $a, version: $info.Version,
            serverType: "jellyfin", loginDisclaimer: null,
            splashscreenEnabled: false, setupCompleted: true,
            dateAdded: $t, dateLastAccessed: $t
          }
        | tojson)
    ' "$prefs") && printf '%s\n' "$neu" > "$prefs.neu" && mv "$prefs.neu" "$prefs"
  '';
in

stdenv.mkDerivation rec {
  pname = "moonfin";
  version = "2.7.0";

  src = fetchurl {
    url = "https://github.com/Moonfin-Client/Moonfin-Core/releases/download/${version}/Moonfin_Linux_v${version}.tar.gz";
    hash = "sha256-b6llMdnUqTyzBPfId1SI6LhNm9KzgwFNo3PY0eRdMuE=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper wrapGAppsHook3 ];

  buildInputs = [
    gtk3
    glib
    pango
    cairo
    harfbuzz
    atk
    gdk-pixbuf
    zlib
    libepoxy
    libsecret
    libarchive
    libGL
    libva
    vulkan-loader
    mpv-unwrapped
    webkitgtk_4_1
    libsoup_3
    SDL2
    libpulseaudio
    alsa-lib
    stdenv.cc.cc.lib
  ];

  # Per dlopen geladen, steht also in keinem NEEDED: EGL/GL (libepoxy),
  # libmpv (media_kit), Vulkan und libva (mpv-Hardware-Dekodierung).
  runtimeDependencies = [ libGL vulkan-loader libva (lib.getLib mpv-unwrapped) ];

  # libdartjni.so verlangt libjvm.so — nur unter Android in Gebrauch.
  autoPatchelfIgnoreMissingDeps = [ "libjvm.so" ];

  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    # Das Programm sucht data/ und lib/ neben /proc/self/exe — der Bündelaufbau
    # bleibt deshalb erhalten.
    mkdir -p $out/lib/moonfin/lib $out/bin
    cp -r data moonfin-bin $out/lib/moonfin/
    for f in lib/*; do
      case "$(basename "$f")" in
        libapp.so | libflutter_linux_gtk.so | lib*_plugin.so \
          | libpdfium.so | libsqlite3.so | libdartjni.so)
          cp -P "$f" $out/lib/moonfin/lib/ ;;
      esac
    done

    cp -r share $out/
    substituteInPlace $out/share/applications/org.moonfin.linux.desktop \
      --replace-fail "Exec=moonfin" "Exec=$out/bin/moonfin"

    runHook postInstall
  '';

  # Upstreams Startskript (moonfin) prüft nur per ldd, ob Bibliotheken fehlen;
  # das ersetzt der Wrapper. LD_LIBRARY_PATH: Dart lädt sqlite und libmpv per
  # dlopen über den Namen, nicht über den RUNPATH.
  postFixup = ''
    makeWrapper $out/lib/moonfin/moonfin-bin $out/bin/moonfin \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "$out/lib/moonfin/lib:${lib.makeLibraryPath [ (lib.getLib mpv-unwrapped) libGL vulkan-loader libva ]}" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      ${lib.optionalString (serverUrl != null) "--run ${serverEintragen}"}
  '';

  meta = {
    description = "Jellyfin- und Emby-Client (Flutter, Release-Bau)";
    homepage = "https://github.com/Moonfin-Client/Moonfin-Core";
    license = lib.licenses.gpl2Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "moonfin";
  };
}
