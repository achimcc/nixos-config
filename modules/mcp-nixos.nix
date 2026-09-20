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
  mcp-nixos = inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Der Name, unter dem die Werkzeuge im Modell auftauchen („nixos"), folgt der
  # Empfehlung von upstream. `type` ist das, was `claude mcp add` selbst
  # schreibt — ohne das Feld fällt Claude Code zwar auf stdio zurück, aber wir
  # legen es fest, statt uns auf einen Vorgabewert zu verlassen.
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-nixos";
    args = [ ];
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
