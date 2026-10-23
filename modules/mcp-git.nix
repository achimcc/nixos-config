# mcp-server-git — Git-Repos lesen UND schreiben als MCP-Server fuer Claude
# Code (github.com/modelcontextprotocol/servers, src/git), 2026-10-11 auf
# Achims Wunsch, global, mit Schreibzugriff. Paket aus nixpkgs, mit EINEM Patch.
#
# DER PATCH, und warum ohne ihn der Schreibzugriff nichts taugt. Upstream
# (2026.8.31, mcp_server_git/server.py):
#
#     def git_commit(repo, message):
#         commit = repo.index.commit(message)
#
# Das ist GitPythons eigener Commit, nicht `git commit`: KEINE Signatur
# (commit.gpgsign wird nicht gelesen), KEIN pre-commit-Hook. Im homeserver-Repo
# hiesse das: ein unsignierter Commit, den hs-riegel und
# signaturen-pruefen.sh vor dem Deploy ablehnen, und die vier `*-gen`-Dateien
# blieben unerzeugt. Der Patch laesst `git_commit` stattdessen das echte
# `git commit -m` fahren — mit der Konfiguration des Repos, also signiert und
# durch die Hooks. Schlaegt ein Hook fehl, kommt dessen Meldung als Fehler des
# Werkzeugs zurueck.
#
# `--replace-fail`: Aendert upstream die Zeile, wird der Bau rot statt still
# wieder unsigniert. `preCheck` gibt den Tests eine Identitaet — `git commit`
# verlangt eine, GitPythons eigener Commit erfand sich eine.
#
# WAS MAN TROTZDEM KENNEN MUSS: `git_reset` nimmt den GANZEN Index zurueck,
# `git_checkout` wechselt den Zweig eines Worktrees — auch unter einer
# Parallelsitzung weg, wenn `repo_path` auf deren Baum zeigt.
#
# KEIN `--repository`: Der Server soll in jedem Projekt arbeiten, das Repo
# nennt jeder Aufruf selbst (`repo_path`).
#
# Eingetragen wie bei mcp-nixos.nix in ~/.claude.json (user scope); die
# Begruendung fuer das Aktivierungsskript statt eines Symlinks steht dort.
{ pkgs, id, ... }:

let
  mcp-server-git = pkgs.mcp-server-git.overridePythonAttrs (alt: {
    postPatch = (alt.postPatch or "") + ''
      substituteInPlace src/mcp_server_git/server.py \
        --replace-fail 'commit = repo.index.commit(message)' \
                       'repo.git.commit("-m", message); commit = repo.head.commit'
    '';
    preCheck = (alt.preCheck or "") + ''
      export GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid
      export GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid
    '';
  });

  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-ohne-schluessel";
    args = [ "/run/current-system/sw/bin/mcp-server-git" ];
    env = { };
  };
in
{
  environment.systemPackages = [ mcp-server-git ];

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
              .mcpServers = ((.mcpServers // {}) + { git: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-git: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
