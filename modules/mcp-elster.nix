# elster-mcp-server fuer Claude Code — bedient das ELSTER-Webportal per
# Puppeteer (github.com/lukasschwarz/elster-mcp-server). 2026-10-09 auf Achims
# Wunsch, global. Paket: pkgs/elster-mcp-server.
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
# WAS MAN WISSEN MUSS: `elster_config_show` verdeckt nur das Passwort.
# Steuernummer und Anschrift gibt es an das Modell zurueck, und die
# Fortschrittsmeldungen der Sitzungen nennen die Steuernummer ebenfalls.
{ config, pkgs, id, ... }:

let
  wrapper = pkgs.writeShellApplication {
    name = "elster-mcp-sops";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
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
      lauf="$XDG_RUNTIME_DIR/elster-mcp"
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
      exec ${pkgs.elster-mcp-server}/bin/elster-mcp-server "$@"
    '';
  };

  # Pfad ueber /run/current-system statt Store-Pfad — Begruendung in
  # modules/mcp-nixos.nix.
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/elster-mcp-sops";
    args = [ ];
    env = { };
  };

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
      # Server in ~/.claude.json (user scope, s. mcp-nixos.nix). Idempotent;
      # eine Datei, die kein gueltiges JSON ist, bleibt unberuehrt.
      home.activation.claudeMcpElster = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { elster: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-elster: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
