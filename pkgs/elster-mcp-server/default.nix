# elster-mcp-server — MCP-Server, der das ELSTER-Webportal per Puppeteer bedient
# (github.com/lukasschwarz/elster-mcp-server). Einbindung und Konfiguration:
# modules/mcp-elster.nix.
#
# Upstream hat weder Tags noch Releases — deshalb auf den COMMIT gepinnt. Der
# Stand ist am 2026-10-09 gelesen worden (2541 Zeilen TypeScript): einzige
# Netzziele sind die sechs elster.de-Adressen in src/elster/constants.ts, kein
# child_process, alle 118 Abhaengigkeiten kommen von registry.npmjs.org. Wer
# `rev` anhebt, liest den Unterschied vorher — das Programm bekommt das
# ELSTER-Zertifikat samt Passwort in die Hand.
#
# ZWEI NixOS-Eigenheiten:
#
#  1. Puppeteers Installationsskript laedt ein eigenes Chromium (~150 MB) nach
#     ~/.cache/puppeteer. Im Bau gibt es kein Netz, und das Binary liefe hier
#     ohnehin nicht (fremder Loader). PUPPETEER_SKIP_DOWNLOAD schaltet das ab.
#
#  2. Stattdessen zeigt PUPPETEER_EXECUTABLE_PATH auf das Chromium aus nixpkgs.
#     `puppeteer.launch()` liest die Variable selbst; im Quelltext steht kein
#     `executablePath`, das sie ueberstimmen wuerde.
{ lib
, buildNpmPackage
, fetchFromGitHub
, makeWrapper
, chromium
}:

buildNpmPackage {
  pname = "elster-mcp-server";
  version = "0.1.0-unstable-2026-07-13";

  src = fetchFromGitHub {
    owner = "lukasschwarz";
    repo = "elster-mcp-server";
    rev = "baa029dcb414bab5e2240cbfa062978bde49ae9e";
    hash = "sha256-nwJLSB9Sq9q7jWl0nmYQabNsLerpfRwGtO+JYfJnHj0=";
  };

  npmDepsHash = "sha256-B3JdhIXUWMnd8HVwzASGXua6npSb3nNSilL8ENGZ1XU=";

  env.PUPPETEER_SKIP_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/elster-mcp-server \
      --set-default PUPPETEER_EXECUTABLE_PATH ${lib.getExe chromium}
  '';

  meta = {
    description = "MCP-Server fuer das ELSTER-Portal (UStVA, EUeR, ESt, Posteingang) per Puppeteer";
    homepage = "https://github.com/lukasschwarz/elster-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "elster-mcp-server";
    platforms = lib.platforms.linux;
  };
}
