# mcp-nixos — MCP-Server mit echten NixOS-Daten (github.com/utensils/mcp-nixos).
#
# Warum überhaupt: Ein Sprachmodell erfindet Paketnamen und Modul-Optionen, die
# es nie gab. Dieser Server fragt stattdessen search.nixos.org, die Home-Manager-
# und nix-darwin-Optionen, NixHub und das Wiki ab. Zwei Werkzeuge, rund 1000
# Token Kontext — er verdient seinen Platz.
#
# ZWEI TEILE:
#
#  1. Das Binary SYSTEMWEIT — wie gestalt und lotse. Der Server soll in JEDEM
#     Projekt zur Verfügung stehen und nicht an einer geladenen devShell hängen.
#     `/run/current-system/sw/bin/mcp-nixos` statt des Store-Pfads: Der bliebe
#     nach einem Update in der Konfigurationsdatei stehen und zeigte nach einer
#     Garbage Collection ins Leere.
#
#  2. Der Eintrag im „user scope" von Claude Code. NACHGEMESSEN, nicht geraten
#     (claude 2.1.278):
#       - `mcpServers` in ~/.claude/settings.json      → wird IGNORIERT
#       - `.mcp.json` im Konfigurationsverzeichnis     → wird IGNORIERT
#       - `mcpServers` in ~/.claude.json               → wirkt, in jedem Projekt
#       - Plugin-Verzeichnis über `--plugin-dir`       → wirkt, aber nur dort,
#         wo jemand das Flag mitgibt (also nicht beim Start aus GNOME/IDE)
#     Deshalb ~/.claude.json.
#
# WARUM EIN AKTIVIERUNGSSKRIPT UND KEIN SYMLINK: ~/.claude.json ist Claude Codes
# eigene Zustandsdatei (Projektliste, Zähler, Onboarding-Stand) und wird
# laufend neu geschrieben. Als Link in den Store wäre sie schreibgeschützt und
# Claude Code startete nicht mehr. Das Skript setzt deshalb genau EINEN
# Schlüssel — idempotent, alles andere bleibt unberührt. Eine Datei, die kein
# gültiges JSON ist, fasst es nicht an.
#
# Einschränkung, die man kennen muss: Läuft während `nixos-rebuild switch` eine
# Claude-Code-Sitzung, kann sie die Datei zwischen Lesen und Schreiben selbst
# anfassen; dann gewinnt der zuletzt geschriebene Stand. Gleiches gilt für den
# lotse-Hook in modules/lotse.nix. In der Praxis hat der Eintrag beim nächsten
# Rebuild wieder Bestand.
{ pkgs, inputs, id, ... }:

let
  # EIN Test abgewählt, die übrigen 380 laufen weiter:
  # `test_startup_survives_non_utf8_dotenv` startet `import mcp_nixos.server` in
  # einem frischen Prozess mit `timeout=60`. Auf einer ausgelasteten Maschine
  # reißt das Limit — gemessen 2026-10-08: derselbe Testlauf 536 s im vollen
  # Rebuild (Load 16, Swap belegt), 33 s einzeln. Der Fehlschlag kippte den
  # ganzen Systembau nach 20 Minuten. Der Test prüft kein Verhalten, das hier
  # von der Last abhinge, nur die Uhr. `checkPhase` ist bei upstream wörtlich
  # `pytest tests/ -m unit`; ändert upstream das, muss diese Zeile mit.
  # `installCheckPhase`, nicht `checkPhase`: buildPythonApplication benennt
  # das um (an der Derivation gemessen: doCheck leer, doInstallCheck = 1) —
  # ein überschriebenes `checkPhase` liefe nie.
  #
  # ENDLOSREKURSION seit nixpkgs 3ec6363 (flake.lock vom 2026-10-25): nixpkgs
  # fuehrt jetzt selbst mcp 2.2.0 und mcp-types, und mcp-types holt seine
  # Version per `inherit (mcp) version` aus dem ENDSTAND des Pakets. Die
  # fastmcp4-Erweiterung von mcp-nixos v3.1.0 (nix/fastmcp4.nix, `keepMcp`)
  # entscheidet ueber `mcp` aber gerade anhand von `pyPrev.mcp-types.version`
  # — die Version haengt also an sich selbst ("infinite recursion encountered"
  # in mcp-types/default.nix:17). Abhilfe: In einem Scope NUR fuer mcp-nixos
  # bekommt mcp-types das `mcp` der Vorstufe; dessen Version ist ein Literal.
  # Damit gilt keepMcp, und mcp-nixos nimmt mcp 2.2.0 aus nixpkgs. Gebaut
  # wird ueber `lib.mkMcpNixos` mit dem System-pkgs statt ueber
  # `packages.default`, das ein eigenes nixpkgs samt set-weitem Overlay
  # auswertet. Entfernen, sobald upstream keepMcp ohne mcp-types entscheidet.
  pythonFuerMcpNixos = pkgs.python3Packages.overrideScope (_: pyprev: {
    mcp-types = pyprev.mcp-types.override { mcp = pyprev.mcp; };
  });

  mcp-nixos = (inputs.mcp-nixos.lib.mkMcpNixos {
    inherit pkgs;
    python3Packages = pythonFuerMcpNixos;
  }).overrideAttrs (_: {
    installCheckPhase = ''
      pytest tests/ -m unit \
        --deselect tests/test_env_file_safety.py::test_startup_survives_non_utf8_dotenv
    '';
  });

  # Der Name, unter dem die Werkzeuge im Modell auftauchen („nixos"), folgt der
  # Empfehlung von upstream. `type` ist das, was `claude mcp add` selbst
  # schreibt — ohne das Feld fällt Claude Code zwar auf stdio zurück, aber wir
  # legen es fest, statt uns auf einen Vorgabewert zu verlassen.
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-ohne-schluessel";
    args = [ "/run/current-system/sw/bin/mcp-nixos" ];
    env = { };
  };
in
{
  environment.systemPackages = [ mcp-nixos ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeMcpNixos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { nixos: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-nixos: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
