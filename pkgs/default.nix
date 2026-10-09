# Custom packages overlay
{ pkgs }:

{
  shadow-simulator = pkgs.callPackage ./shadow { };
  hs-riegel = pkgs.callPackage ./hs-riegel { };
  elster-mcp-server = pkgs.callPackage ./elster-mcp-server { };

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
    })
  ];
}
