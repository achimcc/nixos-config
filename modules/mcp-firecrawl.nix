# firecrawl-mcp — MCP-Server fuer Firecrawl (Scrapen, Crawlen, Suchen im Web),
# 2026-09-28 auf Achims Wunsch. Global fuer alle Projekte.
#
# Gleiche Bauart wie modules/mcp-nixos.nix (dort steht, WARUM ~/.claude.json
# und warum ein Aktivierungsskript statt eines Links). Hier nur das, was anders
# ist:
#
# DER SCHLUESSEL: Der Server spricht mit der Firecrawl-Cloud
# (api.firecrawl.dev) und braucht dafuer FIRECRAWL_API_KEY. Der Schluessel
# liegt in sops (`firecrawl-api-key`) und NICHT im `env`-Block von
# ~/.claude.json — die Datei ist Claude Codes Zustandsdatei, landet in
# Sicherungen und wird von jeder Sitzung gelesen. Ein Wrapper liest den
# Schluessel erst beim Start des Servers aus /run/secrets.
#
# WARUM EIN WRAPPER UND NICHT DIE NUSHELL: Claude Code startet MCP-Server auch
# aus GNOME oder der IDE, ohne Login-Shell. Eine Umgebungsvariable aus
# config.nu kaeme dort nie an.
#
# REIHENFOLGE BEIM EINRICHTEN: Der Eintrag `firecrawl-api-key` muss in
# secrets/secrets.yaml stehen, BEVOR dieses Modul geschaltet wird. Fehlt er,
# bricht sops-nix die Aktivierung ab.
#
# Das Paket kommt aus nixpkgs; Firecrawls Plugin im Claude-Marktplatz ist
# kein MCP-Server, sondern Skills um eine CLI.
{ config, pkgs, id, ... }:

let
  wrapper = pkgs.writeShellApplication {
    name = "firecrawl-mcp-sops";
    text = ''
      schluessel=${config.sops.secrets."firecrawl-api-key".path}
      if [ ! -r "$schluessel" ]; then
        echo "firecrawl-mcp: $schluessel fehlt oder ist nicht lesbar — kein API-Schluessel." >&2
        exit 1
      fi
      FIRECRAWL_API_KEY="$(tr -d '[:space:]' < "$schluessel")"
      export FIRECRAWL_API_KEY
      exec ${pkgs.firecrawl-mcp}/bin/firecrawl-mcp "$@"
    '';
  };

  # Pfad ueber /run/current-system statt Store-Pfad — Begruendung in
  # modules/mcp-nixos.nix.
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/firecrawl-mcp-sops";
    args = [ ];
    env = { };
  };
in
{
  sops.secrets."firecrawl-api-key" = {
    owner = id.username;
    mode = "0400";
  };

  environment.systemPackages = [ wrapper ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeMcpFirecrawl = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { firecrawl: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-firecrawl: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
