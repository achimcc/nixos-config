# mcp-server-filesystem — Dateizugriff als MCP-Server fuer Claude Code
# (github.com/modelcontextprotocol/servers, src/filesystem), 2026-10-11 auf
# Achims Wunsch, global. Paket aus nixpkgs.
#
# WAS ER DARF: lesen, auflisten, suchen — unter `verzeichnisse`. Die vier
# schreibenden Werkzeuge (`write_file`, `edit_file`, `create_directory`,
# `move_file`) sind gesperrt, aus zwei Gruenden:
#
#  1. Sie gehen an den Hooks vorbei. `claude-riegel nix-parse` haengt an
#     Edit/Write/MultiEdit und liest `tool_input.file_path`; ein
#     `mcp__filesystem__write_file` traegt `path` und einen anderen Namen —
#     eine kaputte .nix-Datei fiele erst in der Serverauswertung auf.
#  2. Claude Codes eigene Edit/Write fuehren Buch (Rueckspulen, „Datei seit
#     dem Lesen geaendert"); der MCP-Weg tut beides nicht.
#
# Der Server kennt keinen Nur-Lese-Schalter (upstream nur ueber
# Docker-ro-Mounts). Die Sperre steht deshalb in `permissions.deny` von
# ~/.claude/settings.json, wie bei mcp-git.nix; freigeben = aus `gesperrt`
# streichen.
#
# ZWEI DINGE, DIE MAN KENNEN MUSS:
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
  name = "filesystem";

  verzeichnisse = [
    "/home/${id.username}/Projects"
    "/home/${id.username}/nixos-config"
  ];

  alle = [
    "write_file"
    "edit_file"
    "create_directory"
    "move_file"
  ];
  gesperrt = alle;

  regel = w: "mcp__${name}__${w}";

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
              .mcpServers = ((.mcpServers // {}) + { ${name}: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-filesystem: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi

        # Die Sperre: erst JEDEN Eintrag dieses Moduls heraus, dann die
        # gesperrten hinein — so wirkt auch eine Freigabe.
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq \
              --argjson alle ${lib.escapeShellArg (builtins.toJSON (map regel alle))} \
              --argjson gesperrt ${lib.escapeShellArg (builtins.toJSON (map regel gesperrt))} '
              .permissions.deny = (((.permissions.deny // []) - $alle) + $gesperrt)
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-filesystem: $datei ist kein gueltiges JSON — die Sperre wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
