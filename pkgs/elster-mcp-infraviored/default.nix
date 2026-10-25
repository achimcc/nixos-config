# elster-mcp-server, Fork von Infraviored (github.com/Infraviored/elster-mcp-server)
# — ZUM PARALLELEN TEST neben pkgs/elster-mcp-server (2026-10-25). Einbindung:
# modules/mcp-elster.nix als Server `elsterneu` im Steuer-Repo.
#
# Was der Fork anders macht: Nach EINEM Puppeteer-Login spielt er die
# Formular-POSTs des Portals per fetch im ELSTER-Tab nach und adressiert Felder
# ueber die ERiC-Kennzahl (elster_form_open/page/set/save/check/review) statt
# per Klick. Das soll die Klickfallen aus ~/Dokumente/Steuer/CLAUDE.md
# (Modal, unsichtbare Vorlagenfelder, Navigation-Timeout) umgehen — noch nicht
# gemessen.
#
# Gelesen am 2026-10-25 (Review im Steuer-Repo, Sitzung „Steuer-Werkzeuge"):
# HEAD a2139dc vom 2026-10-04, 13 Commits eines Autors auf baa029d, +4170/−1672.
# Netzziele nur www.elster.de/eportal (src/elster/constants.ts), alle fetch
# relativ im ELSTER-Tab, keine Telemetrie. KEIN Request-Filter im Browser
# (base.ts ohne setRequestInterception). Sendesperre: Befehls-Allowlist plus
# Regex (engine-driver.ts:31-55), Knopfdruecke auf der Versenden-Seite
# gesperrt. Lockfile byte-gleich mit baa029d → derselbe npmDepsHash. Neu:
# child_process fuer pdfinfo/pdftoppm (belege.ts) → poppler-utils im PATH.
# Wer `rev` anhebt, liest den Unterschied vorher.
#
# Die riskanten Werkzeuge (form_handoff, form_new, Uploads, eDaten-Abruf mit
# neuem Formular) sind auf Achims Wunsch NICHT gesperrt, s. claude-riegel.nix.
{ lib
, buildNpmPackage
, fetchFromGitHub
, makeWrapper
, chromium
, poppler-utils
}:

buildNpmPackage {
  pname = "elster-mcp-infraviored";
  version = "0.1.0-unstable-2026-10-04";

  src = fetchFromGitHub {
    owner = "Infraviored";
    repo = "elster-mcp-server";
    rev = "a2139dced38762c50d3701db1dc281e08a999c49";
    hash = "sha256-kFPJBCmzeOmn2HHYvrN6k49ZAf6ruc+tVI345C6KKXE=";
  };

  npmDepsHash = "sha256-B3JdhIXUWMnd8HVwzASGXua6npSb3nNSilL8ENGZ1XU=";

  env.PUPPETEER_SKIP_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/elster-mcp-server \
      --set-default PUPPETEER_EXECUTABLE_PATH ${lib.getExe chromium} \
      --prefix PATH : ${lib.makeBinPath [ poppler-utils ]}
  '';

  meta = {
    description = "MCP-Server fuer das ELSTER-Portal, Formulare per Kennzahl (Fork Infraviored)";
    homepage = "https://github.com/Infraviored/elster-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "elster-mcp-server";
    platforms = lib.platforms.linux;
  };
}
