# mcp-server-git — Git-Repos lesen als MCP-Server fuer Claude Code
# (github.com/modelcontextprotocol/servers, src/git), 2026-10-11 auf Achims
# Wunsch, global. Paket aus nixpkgs.
#
# NUR LESEND, und das ist am Quelltext gemessen, nicht geraten (2026.8.31,
# mcp_server_git/server.py):
#
#     def git_commit(repo, message):
#         commit = repo.index.commit(message)
#
# Das ist GitPythons eigener Commit, nicht `git commit`: KEINE Signatur
# (commit.gpgsign wird nicht gelesen), KEIN pre-commit-Hook. Im homeserver-Repo
# hiesse das: ein unsignierter Commit, den hs-riegel und
# signaturen-pruefen.sh vor dem Deploy ablehnen, und die vier `*-gen`-Dateien
# blieben unerzeugt. Dieselbe Entscheidung wie bei mcp-github.nix
# (`X-MCP-Readonly`): der Server liest, geschrieben wird mit git.
#
# Die uebrigen schreibenden Werkzeuge sind aus demselben Grund aus:
# `git_reset` nimmt den GANZEN Index zurueck, `git_checkout` wechselt den Zweig
# eines Worktrees unter einer laufenden Sitzung weg, und ein `git_add` ohne
# `git_commit` ist nur ein halber Handgriff.
#
# Der Server kennt selbst keinen Nur-Lese-Schalter. Die Sperre steht deshalb in
# `permissions.deny` von ~/.claude/settings.json — ein verweigertes Werkzeug
# bekommt das Modell gar nicht erst angeboten. Wer ein Werkzeug freigeben will,
# streicht es aus `gesperrt`; das Aktivierungsskript nimmt dann auch den
# Eintrag wieder heraus.
#
# KEIN `--repository`: Der Server soll in jedem Projekt arbeiten, das Repo
# nennt jeder Aufruf selbst (`repo_path`).
#
# Eingetragen wie bei mcp-nixos.nix in ~/.claude.json (user scope); die
# Begruendung fuer das Aktivierungsskript statt eines Symlinks steht dort.
{ pkgs, id, ... }:

let
  name = "git";

  alle = [
    "git_commit"
    "git_add"
    "git_reset"
    "git_checkout"
    "git_create_branch"
  ];
  gesperrt = alle;

  regel = w: "mcp__${name}__${w}";

  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-server-git";
    args = [ ];
    env = { };
  };
in
{
  environment.systemPackages = [ pkgs.mcp-server-git ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeMcpGit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
          echo "mcp-git: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
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
          echo "mcp-git: $datei ist kein gueltiges JSON — die Sperre wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
