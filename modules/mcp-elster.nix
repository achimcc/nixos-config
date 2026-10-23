# elster-mcp-server fuer Claude Code — bedient das ELSTER-Webportal per
# Puppeteer (github.com/lukasschwarz/elster-mcp-server). 2026-10-09 auf Achims
# Wunsch, zunaechst global. Paket: pkgs/elster-mcp-server.
#
# SEIT 2026-10-15 NICHT MEHR GLOBAL: Der Server laedt nur noch im Repo
# ~/Dokumente/Steuer ueber dessen `.mcp.json` (project scope). Ein globaler
# Eintrag brachte in jeder Sitzung jedes anderen Repos 20 Werkzeugschemata
# mit, die dort niemand braucht. Dieses Modul liefert weiter den Wrapper
# `elster-mcp-sops` nach /run/current-system/sw/bin und die drei Secrets; die
# Aktivierung unten RAEUMT den alten globalen Eintrag aus ~/.claude.json ab,
# statt ihn zu setzen (Migration, idempotent).
#
# SEIT 2026-10-22 SCHREIBT DIESES MODUL DIE `.mcp.json` DES STEUER-REPOS
# (home.file, Symlink in den Store; `force`, weil bis dahin eine von Hand
# angelegte Datei dort lag). Sie enthaelt zwei Server: elster und paperless -
# die Steuererklaerung braucht die Belege aus Paperless (Tag steuer-<Jahr>),
# der Eintrag kommt aus mcp-paperless-server.nix. Die Datei ist im Steuer-Repo
# gitignored; nach dem Rebuild braucht es eine neue Claude-Sitzung.
#
# WAS DAS WERKZEUG DARF, bevor man es schaltet: Es meldet sich mit dem
# ELSTER-Zertifikat an. `elster_ustva_confirm` klickt „Absenden" — das ist eine
# abgegebene Umsatzsteuer-Voranmeldung und nicht rueckholbar. EUeR und ESt
# fuellen nur bis „Pruefen", Verlauf und Posteingang lesen nur. Upstream ist
# ein Ein-Personen-Projekt ohne Release; ELSTERs Nutzungsbedingungen koennen
# automatisierten Zugriff einschraenken (README, „Rechtlicher Hinweis").
#
# VORAUSSETZUNG: Drei Eintraege muessen in secrets/secrets.yaml stehen, BEVOR
# dieses Modul geschaltet wird — sonst bricht sops-nix den Bau ab:
#
#   elster-zertifikat        die .pfx-Datei, base64 in EINER Zeile
#                            (`open --raw zert.pfx | encode base64`)
#   elster-passwort          das Zertifikatspasswort
#   elster-steuerpflichtiger ein JSON-Objekt, Felder wie `taxpayer` in
#                            config.example.json von upstream:
#                            {"taxNumber":"…","stateCode":"…","name":"…",
#                             "firstName":"…","street":"…","houseNumber":"…",
#                             "zip":"…","city":"…"}
#
# DREI ENTSCHEIDUNGEN:
#
#  1. Die Konfiguration entsteht bei jedem Start neu in $XDG_RUNTIME_DIR
#     (tmpfs, nur der Nutzer). Upstream liest Passwort und Steuernummer aus
#     einer config.json ODER aus ELSTER_*-Variablen. Variablen erbte das
#     Chromium, das der Server startet, samt jedem seiner Kindprozesse; eine
#     feste Datei im Home laege im Klartext auf der Platte und in jeder
#     Sicherung. jq setzt die Werte per --rawfile/--slurpfile ein — ein
#     Passwort mit Anfuehrungszeichen oder Backslash bleibt gueltiges JSON.
#     Das Zertifikat liegt entschluesselt ebenfalls nur dort; Puppeteer
#     braucht es als Datei, weil es sie ins Anmeldeformular hochlaedt.
#
#  2. Chromium MIT Sandkasten. Upstreams Vorgabe fuer `browserArgs` beginnt mit
#     `--no-sandbox --disable-setuid-sandbox` (gedacht fuer Container als
#     root). Hier laeuft der Browser als Nutzer, der Sandkasten funktioniert
#     (2026-10-09 gemessen: Start ohne die beiden Schalter gelingt), und er
#     verarbeitet eine Sitzung, in der das Steuerkonto offen ist.
#     `browserArgs` laesst sich NUR ueber die Datei setzen, nicht ueber eine
#     Variable — noch ein Grund fuer Entscheidung 1.
#
#  3. Bildschirmfotos und heruntergeladene Bescheide nach
#     ~/.local/share/elster-mcp (0700). Upstreams Vorgabe ist `./screenshots`
#     und `./downloads` relativ zum ARBEITSVERZEICHNIS — bei einem globalen
#     Server also in dem Repo, in dem gerade eine Sitzung laeuft, und von dort
#     einen `git add -A` vom oeffentlichen Commit entfernt.
#
# SPERRE (Audit 4, B173): `elster_ustva_confirm` steht in `permissions.deny`
# (modules/claude-riegel.nix) und laeuft in keiner Sitzung, auch nicht im
# Bypass-Modus. Eine Voranmeldung schickt Achim im Portal selbst ab, oder er
# nimmt den Eintrag fuer genau diese Sitzung bewusst heraus.
#
# WAS MAN WISSEN MUSS: `elster_config_show` verdeckt nur das Passwort.
# Steuernummer und Anschrift gibt es an das Modell zurueck, und die
# Fortschrittsmeldungen der Sitzungen nennen die Steuernummer ebenfalls.
{ config, pkgs, id, ... }:

let
  wrapper = pkgs.writeShellApplication {
    name = "elster-mcp-sops";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      # Audit 4, B171: keine Sitzungsschluessel in der Umgebung des Servers (s. mcp-huelle.nix).
      unset GH_TOKEN GITHUB_TOKEN SOPS_AGE_KEY_FILE SSH_AUTH_SOCK
      zertifikat=${config.sops.secrets."elster-zertifikat".path}
      passwort=${config.sops.secrets."elster-passwort".path}
      person=${config.sops.secrets."elster-steuerpflichtiger".path}
      for f in "$zertifikat" "$passwort" "$person"; do
        if [ ! -r "$f" ]; then
          echo "elster-mcp: $f fehlt oder ist nicht lesbar." >&2
          exit 1
        fi
      done
      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        echo "elster-mcp: XDG_RUNTIME_DIR ist nicht gesetzt — kein Ort fuer die Laufzeit-Konfiguration." >&2
        exit 1
      fi

      umask 077
      # Audit 4, B173: Zertifikat und Passwort lagen dauerhaft entschluesselt in
      # $XDG_RUNTIME_DIR/elster-mcp. Jetzt je Prozess ein eigener Ordner, den
      # ein trap beim Ende loescht - eigener Ordner, damit das Ende EINER
      # Sitzung einer zweiten nicht das Zertifikat unter dem Browser wegzieht.
      # Was ein SIGKILL zuruecklaesst, raeumt der naechste Start ab (Ordner,
      # deren Prozess nicht mehr lebt), ebenso die Dateien der alten Bauart.
      basis="$XDG_RUNTIME_DIR/elster-mcp"
      mkdir -p "$basis"
      chmod 700 "$basis"
      rm -f "$basis/zertifikat.pfx" "$basis/config.json"
      for alt in "$basis"/*/; do
        [ -d "$alt" ] || continue
        pid=$(basename "$alt")
        case "$pid" in *[!0-9]*) continue ;; esac
        kill -0 "$pid" 2>/dev/null || rm -rf "$alt"
      done
      lauf="$basis/$$"
      kind=
      # Inline statt als Funktion: shellcheck (SC2329) sieht einen Namen in
      # trap nicht als Aufruf und bricht den Bau ab.
      trap 'rm -rf "$lauf"' EXIT
      trap '[ -n "$kind" ] && kill -TERM "$kind" 2>/dev/null; exit 143' TERM INT HUP
      daten="''${XDG_DATA_HOME:-$HOME/.local/share}/elster-mcp"
      mkdir -p "$lauf" "$daten/downloads" "$daten/screenshots"
      chmod 700 "$lauf" "$daten"

      if ! tr -d '[:space:]' < "$zertifikat" | base64 -d > "$lauf/zertifikat.pfx"; then
        echo "elster-mcp: elster-zertifikat ist kein gueltiges base64." >&2
        exit 1
      fi

      # Das Passwort verliert nur den Zeilenumbruch am Ende, den der Editor
      # anhaengt — Leerzeichen darin gehoeren zum Passwort.
      if ! jq -n \
            --rawfile passwort "$passwort" \
            --slurpfile person "$person" \
            --arg pfx "$lauf/zertifikat.pfx" \
            --arg daten "$daten" '
            ($person | if length == 1 and (.[0] | type) == "object" then .[0]
                       else error("kein einzelnes JSON-Objekt") end) as $p
            | {
                auth: { pfxPath: $pfx, password: ($passwort | sub("\r?\n$"; "")) },
                taxpayer: ({ country: "DE" } + $p),
                runtime: {
                  downloadDir: ($daten + "/downloads"),
                  screenshotDir: ($daten + "/screenshots"),
                  headless: true,
                  browserArgs: [ "--disable-dev-shm-usage", "--window-size=1280,1024" ]
                }
              }' > "$lauf/config.json"; then
        echo "elster-mcp: elster-steuerpflichtiger ist kein JSON-Objekt — keine Konfiguration geschrieben." >&2
        exit 1
      fi

      export ELSTER_CONFIG_PATH="$lauf/config.json"
      # Kein exec (B173): Der trap braucht die Shell bis zum Ende des Servers.
      # Im Hintergrund, damit TERM sofort ankommt und weitergereicht wird;
      # `<&0`, weil ein Hintergrundjob sonst /dev/null als stdin bekaeme - und
      # stdin ist der MCP-Kanal.
      ${pkgs.elster-mcp-server}/bin/elster-mcp-server "$@" <&0 &
      kind=$!
      rc=0
      wait "$kind" || rc=$?
      exit "$rc"
    '';
  };

  # Der Eintrag fuer ~/Dokumente/Steuer/.mcp.json (project scope), zum
  # Nachlesen — er steht DORT, nicht hier. Pfad ueber /run/current-system
  # statt Store-Pfad, Begruendung in modules/mcp-nixos.nix:
  #   { "mcpServers": { "elster": { "type": "stdio",
  #       "command": "/run/current-system/sw/bin/elster-mcp-sops",
  #       "args": [], "env": {} } } }

  geheim = {
    owner = id.username;
    mode = "0400";
  };
in
{
  sops.secrets."elster-zertifikat" = geheim;
  sops.secrets."elster-passwort" = geheim;
  sops.secrets."elster-steuerpflichtiger" = geheim;

  environment.systemPackages = [ wrapper ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.file."Dokumente/Steuer/.mcp.json" = {
        force = true;
        text = builtins.toJSON {
          mcpServers = {
            elster = {
              type = "stdio";
              command = "/run/current-system/sw/bin/elster-mcp-sops";
              args = [ ];
              env = { };
            };
            paperless = import ./mcp-paperless-server.nix;
          };
        };
      };

      # Den alten globalen Eintrag aus ~/.claude.json ENTFERNEN (bis 2026-10-15
      # setzte diese Stelle ihn). Idempotent: Fehlt er, aendert jq nichts, und
      # die Datei wird nicht angefasst; ist sie kein gueltiges JSON, bleibt sie
      # unberuehrt.
      home.activation.claudeMcpElster = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ -e "$datei" ] && ${pkgs.jq}/bin/jq -e '.mcpServers.elster' "$datei" >/dev/null 2>&1; then
          neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
          if ${pkgs.jq}/bin/jq 'del(.mcpServers.elster)' "$datei" > "$neu"; then
            run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
            run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
          else
            ${pkgs.coreutils}/bin/rm -f "$neu"
            echo "mcp-elster: $datei ist kein gueltiges JSON — alter Eintrag NICHT entfernt." >&2
          fi
        fi
      '';
    };
}
