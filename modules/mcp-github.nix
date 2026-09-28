# GitHub-MCP fuer Claude Code — GitHubs gehosteter Server
# (api.githubcopilot.com/mcp), NUR LESEND, Token nicht in der Umgebung.
#
# WARUM NICHT DAS PLUGIN `github@claude-plugins-official`: Dessen .mcp.json
# setzt `Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}`. Die Variable
# gibt es hier nicht (nushell exportiert GH_TOKEN, home.nix), der Kopf wird zu
# `Bearer ` und der Server antwortet beim Start jeder Sitzung mit
# „Authorization header is badly formatted" (2026-09-28 gemessen). Die Datei
# liegt im Plugin-Cache und wird bei jedem Update ueberschrieben — dort ist
# nichts zu reparieren. Das Plugin ist deshalb AUSGESCHALTET (Liste `aus` in
# modules/claude-plugins.nix) und der Server hier selbst eingetragen.
#
# DREI ENTSCHEIDUNGEN:
#
#  1. `headersHelper` statt `headers`: Claude Code ruft das Skript beim
#     Verbinden auf und nimmt dessen JSON als Kopfzeilen. Der Token kommt so
#     direkt aus sops (/run/secrets/github-token) und steht weder in
#     ~/.claude.json noch in einer Umgebungsvariable, die jeder Hook erbt
#     (dieselbe Lehre wie beim ANTHROPIC_API_KEY in home.nix). jq liest ihn per
#     --rawfile — nicht ueber argv.
#
#  2. `X-MCP-Readonly: true`: Der Server bietet dann nur lesende Werkzeuge an.
#     Schreibende (Datei per API pushen, PR mergen) legten UNSIGNIERTE Commits
#     auf `main` des homeserver-Repos — genau das, was hs-riegel vor dem Deploy
#     ablehnt. Schreiben bleibt bei git und `gh`.
#
#  3. Kein eigenes Binary: der Server laeuft bei GitHub, hier liegt nur das
#     Kopfzeilen-Skript.
{ config, pkgs, id, ... }:

let
  kopfzeilen = pkgs.writeShellApplication {
    name = "github-mcp-kopfzeilen";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      token=${config.sops.secrets."github-token".path}
      if [ ! -r "$token" ]; then
        echo "github-mcp: $token fehlt oder ist nicht lesbar — kein Token." >&2
        exit 1
      fi
      jq -cn --rawfile t "$token" \
        '{"Authorization": ("Bearer " + ($t | gsub("\\s"; ""))), "X-MCP-Readonly": "true"}'
    '';
  };

  # Pfad ueber /run/current-system statt Store-Pfad — Begruendung in
  # modules/mcp-nixos.nix.
  server = builtins.toJSON {
    type = "http";
    url = "https://api.githubcopilot.com/mcp/";
    headersHelper = "/run/current-system/sw/bin/github-mcp-kopfzeilen";
  };
in
{
  environment.systemPackages = [ kopfzeilen ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      # Server in ~/.claude.json (user scope, s. mcp-nixos.nix). Idempotent;
      # eine Datei, die kein gueltiges JSON ist, bleibt unberuehrt.
      home.activation.claudeMcpGithub = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { github: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-github: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
