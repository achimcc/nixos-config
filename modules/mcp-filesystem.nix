# mcp-server-filesystem — Dateizugriff als MCP-Server fuer Claude Code
# (github.com/modelcontextprotocol/servers, src/filesystem), 2026-10-11 auf
# Achims Wunsch, global, mit Schreibzugriff. Paket aus nixpkgs.
#
# WAS ER DARF: lesen, auflisten, suchen, schreiben, verschieben — unter
# `verzeichnisse`, nirgends sonst.
#
# DREI DINGE, DIE MAN KENNEN MUSS:
#
#  - `write_file` und `edit_file` haben einen anderen Namen und ein anderes
#    Feld (`path`) als Claude Codes Edit/Write. Der Hook `claude-riegel
#    nix-parse` haengt deshalb AUCH an diesen beiden (modules/claude-riegel.nix)
#    — sonst fiele eine kaputte .nix-Datei erst in der Serverauswertung auf.
#    Was der MCP-Weg nicht hat: Claude Codes Buchfuehrung (Rueckspulen, „Datei
#    seit dem Lesen geaendert"). `write_file` ueberschreibt ohne Rueckfrage.
#
#  - Ein Ergebnis geht ROH in den Chat, an gestalt vorbei. Eine JSON-, YAML-
#    oder .env-Datei liest man weiter ueber Bash mit gestalt bzw. der
#    Wertzeilen-Maske, nicht ueber `read_text_file`. Deshalb stehen hier nur
#    Quellbaeume und NICHT $HOME: ~/.ssh, ~/.config und ~/.claude bleiben
#    draussen. ~/Projects/homeserver-secrets liegt darunter, ist aber
#    sops-verschluesselt.
#
#  - Die Liste unten ist nur der VORGABEWERT. Meldet der Client MCP-Roots,
#    ersetzt der Server seine erlaubten Verzeichnisse durch diese
#    (dist/index.js, `updateAllowedDirectoriesFromRoots`). Ob Claude Code das
#    tut, ist nach dem Rebuild zu messen: `list_allowed_directories`.
#
# Eingetragen wie bei mcp-nixos.nix in ~/.claude.json (user scope); die
# Begruendung fuer das Aktivierungsskript statt eines Symlinks steht dort.
{ pkgs, id, ... }:

let
  verzeichnisse = [
    "/home/${id.username}/Projects"
    "/home/${id.username}/nixos-config"
  ];

  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-server-filesystem";
    args = verzeichnisse;
    env = { };
  };
in
{
  environment.systemPackages = [ pkgs.mcp-server-filesystem ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeMcpFilesystem = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { filesystem: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-filesystem: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
