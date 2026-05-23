{ lib, appimageTools, fetchurl, runCommand }:

let
  pname = "moonfin";
  version = "1.4.0";

  src = fetchurl {
    url = "https://github.com/Moonfin-Client/Mobile-Desktop/releases/download/${version}/Moonfin_Linux_v${version}.AppImage";
    hash = "sha256-nk+eVJMR+wxOrWLYYRG+yx5+FAI6XrijCb4lvSiLb94=";
  };

  rawExtract = appimageTools.extractType2 { inherit pname version src; };

  # Patch: Bundled libs, die mit System-Loader-Plugins kollidieren.
  # Muster: System-Plugin (gdk-pixbuf-SVG-Loader, ALSA-PipeWire-Plugin, …)
  # wird gegen eine bestimmte lib-Version gebaut, die AppImage bundelt aber
  # eine ältere. Der bundled Pfad shadowed die FHS-Version → Symbol-Mismatch.
  #   - librsvg-2.so (2.50 bundled ↔ 2.61 System): rsvg_handle_get_pixbuf_and_error
  #   - libpipewire-0.3.so (0.3.100 bundled ↔ 1.6 System): _snd_ctl_pipewire_open
  appimageContents = runCommand "${pname}-${version}-patched" { } ''
    cp -r ${rawExtract} $out
    chmod -R +w $out
    rm -f $out/lib/librsvg-2.so*
    rm -f $out/lib/libpipewire-0.3.so*
  '';
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;

  # Tauri/webkit2gtk-App – libepoxy fehlt im default FHS; weitere
  # typische webkit2gtk-Runtime-Deps präventiv mit, damit Player,
  # DBus-Tray, HTTP etc. sauber laufen.
  extraPkgs = p: [
    p.libepoxy
    p.webkitgtk_4_1
    p.libsoup_3
    p.libayatana-appindicator
    # X11/Video extensions – für Jellyfin-Playback essentiell
    p.libxv                    # X Video extension (HW video output)
    p.libxscrnsaver            # Screensaver-Inhibit bei Playback
    p.libxtst
    p.libvdpau                 # NVIDIA-artige VDPAU-Fallbacks
    # VA-API Stack – matcht dein hwdec="vaapi-copy" mpv-Setup
    p.libva
    p.intel-media-driver
    p.libdrm
    p.mesa
    # Audio-Stack (nach Entfernen der bundled libpipewire)
    p.pipewire
    p.alsa-lib
    p.libpulseaudio
  ];

  extraInstallCommands = ''
    # AppImage liefert reverse-DNS-Namen: org.moonfin.linux.{desktop,png}
    # Desktop-Datei nach share/applications, Icon-Name (Icon=org.moonfin.linux)
    # muss als Pixmap oder in der hicolor-Hierarchie auffindbar bleiben.
    install -Dm644 ${appimageContents}/org.moonfin.linux.desktop \
      $out/share/applications/org.moonfin.linux.desktop
    install -Dm644 ${appimageContents}/org.moonfin.linux.png \
      $out/share/pixmaps/org.moonfin.linux.png
  '';

  meta = {
    description = "Moonfin – erweiterter Desktop-Client für Jellyfin/Emby";
    homepage = "https://github.com/Moonfin-Client/Mobile-Desktop";
    changelog = "https://github.com/Moonfin-Client/Mobile-Desktop/releases/tag/${version}";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
