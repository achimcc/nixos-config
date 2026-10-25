# Custom packages overlay
{ pkgs }:

{
  shadow-simulator = pkgs.callPackage ./shadow { };
  hs-riegel = pkgs.callPackage ./hs-riegel { };
  elster-mcp-server = pkgs.callPackage ./elster-mcp-server { };
  elster-mcp-infraviored = pkgs.callPackage ./elster-mcp-infraviored { };
  paperless-ngx-mcp = pkgs.callPackage ./paperless-ngx-mcp { };
  moonfin = pkgs.callPackage ./moonfin { };

  # WiVRn auf 26.6.2 festgehalten (2026-10-12) - dieselbe Version wie vr-01 auf
  # dem Homeserver, damit EIN Client auf der Quest beide Server bedient.
  # Ursache, Herkunft und Ende der Abweichung: Kopf von pkgs/wivrn/package.nix.
  wivrn = pkgs.callPackage ./wivrn/package.nix { };

  # WayVR mit gepatchtem cpal 0.17.3 (2026-10-12).
  # Ursache: Nach EINEM Audio-Underrun meldet das PipeWire-ALSA-Plugin POLLERR,
  # bis jemand `snd_pcm_prepare` ruft (pcm_pipewire.c, `xrun_detected`). cpal
  # 0.17.3 meldet den Fehler nur und pollt weiter - der Audio-Thread dreht mit
  # rund 150 000 Runden je Sekunde leer, rodio schreibt jede als
  # "audio stream error: ... `alsa::poll()` returned POLLERR" nach stderr. Am
  # 2026-10-12 waren das 546 260 Journalzeilen in zwoelf Minuten; das
  # Nutzerjournal reichte danach nur noch 20 Minuten zurueck. Ausloeser ist ein
  # Audio-Thread, der nicht drankommt (ueberlastete Maschine) - nachgestellt mit
  # SIGSTOP fuer 0,5 s: ohne Patch Dauerschleife und nie wieder Ton, mit Patch
  # ein Underrun und weiter.
  # Der Patch schickt POLLERR in cpals vorhandenen XRun-Zweig (`prepare`).
  # Der Verzeichnisname ist mit Absicht fest: Hebt WayVR cpal an, scheitert der
  # Bau hier - dann pruefen, ob die neue Fassung POLLERR selbst behebt (der
  # Hauptzweig von cpal tut es), und den Patch streichen.
  wayvr = pkgs.wayvr.overrideAttrs (alt: {
    postPatch = (alt.postPatch or "") + ''
      patch -p1 -d "$cargoDepsCopy"/source-registry-0/cpal-0.17.3 < ${./wayvr/cpal-pollerr.patch}
    '';
  });

  # anyio-Tests unter Python 3.12 abgeschaltet (2026-10-09).
  # Ursache: Python 3.12.15 lehnt in SSLObject._create `server_hostname` im
  # Servermodus ab; tests/streams/test_tls.py::test_tls_connectable uebergibt
  # genau das -> ValueError. Dazu laufen die pytester-Tests unter Baulast in
  # ihr 20-s-Zeitlimit. python312Packages baut Hydra nicht mehr (python3 ist
  # 3.14), also wird lokal gebaut und geprueft. Betroffen: apostrophe und die
  # openbb-FHS-Umgebung (home.nix). Entfernen, sobald nixpkgs anyio fuer 3.12
  # repariert oder beide Nutzer von 3.12 weg sind.
  pythonPackagesExtensions = pkgs.pythonPackagesExtensions ++ [
    (pyfinal: pyprev: {
      anyio =
        if pyprev.python.pythonVersion == "3.12"
        then pyprev.anyio.overridePythonAttrs (_: { doCheck = false; })
        else pyprev.anyio;

      # pytest-subprocess unter 3.12: test_multiple_wait ist ein Zeitmesstest
      # mit 0,2 s Reserve (Skript laeuft 1 s, Budget 0,2+0,2+0,9 s). Gemessen
      # 2026-10-09: Skript braucht ausserhalb des Sandkastens schon 1,11 s,
      # im Bau reisst es das Budget — auch als Einzelbau, nicht nur unter Last.
      pytest-subprocess =
        if pyprev.python.pythonVersion == "3.12"
        then pyprev.pytest-subprocess.overridePythonAttrs (old: {
          disabledTests = (old.disabledTests or [ ]) ++ [ "test_multiple_wait" ];
        })
        else pyprev.pytest-subprocess;

      # reuse 6.2.0 ohne `man`-Output (2026-10-22, nixpkgs 02c087f / nixos-unstable
      # vom 20.10.): Der sphinx-Hook liest die Builder mit
      # `eval "__sphinxBuilders=($sphinxBuilders)"`. Seit das Paket mit
      # __structuredAttrs gebaut wird, ist sphinxBuilders ein Bash-Array, und
      # `$sphinxBuilders` liefert nur das erste Element `html` - der man-Builder
      # laeuft nie, der Bau endet mit "failed to produce output path for output
      # 'man'". Hydras letzter reuse-Bau stammt vom 15.10., der Cache hat die
      # neue Derivation nicht; amberol (home.nix) zieht reuse herein. Als
      # String kommt die Liste durch den eval wieder als zwei Builder an.
      # Entfernen, sobald der Hook upstream mit Arrays umgeht (Belege:
      # Bau-Log von 04dwwb5j…-python3.14-reuse-6.2.0.drv, setup-hook Zeile 34).
      reuse = pyprev.reuse.overridePythonAttrs (_: { sphinxBuilders = "html man"; });
    })
  ];
}
