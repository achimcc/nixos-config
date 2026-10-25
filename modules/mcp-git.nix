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
# wieder unsigniert. `preCheck` gibt den Tests eine Identitaet als Rueckfall —
# `git commit` verlangt eine, GitPythons eigener Commit erfand sich eine.
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
  # FASSUNG GEHOBEN 2026-10-25: nixpkgs 3ec6363 fuehrt mcp 2.2.0, sein
  # mcp-server-git 2026.8.31 verlangt aber `mcp<2` (pythonRuntimeDepsCheck rot)
  # und benutzt die Dekorator-API (`@server.list_tools()`), die es in mcp 2
  # nicht mehr gibt — `pythonRelaxDeps` braeche zur Laufzeit. Upstream ist seit
  # 15c8b0c6 auf mcp 2 portiert; 2026.10.18 (38fdee2402) verlangt `mcp>=2.2`,
  # das naechste (2026.10.19) schon >=2.3. Neu dabei: jsonschema, und die
  # Tests laufen mit pytest-asyncio. Die Patch-Zeile steht dort unveraendert
  # (server.py:217). Zurueck auf das nixpkgs-Paket, sobald es >= 2026.10.18 ist.
  mcp-server-git = pkgs.mcp-server-git.overridePythonAttrs (alt: {
    version = "2026.10.18";
    src = pkgs.fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "servers";
      rev = "38fdee2402c6f30592aefe700f276814c86b2eeb";
      hash = "sha256-ZiylSx6Gl4d02ukojjT0V+5stfBJ9E9daJwNu3sMpMg=";
    };
    dependencies = (alt.dependencies or [ ]) ++ [ pkgs.python3Packages.jsonschema ];
    nativeCheckInputs = (alt.nativeCheckInputs or [ ]) ++ [ pkgs.python3Packages.pytest-asyncio ];
    postPatch = (alt.postPatch or "") + ''
      substituteInPlace src/mcp_server_git/server.py \
        --replace-fail 'commit = repo.index.commit(message)' \
                       'repo.git.commit("-m", message); commit = repo.head.commit'
    '';
    # Identitaet als GLOBALE Git-Konfiguration, nicht als GIT_AUTHOR_*: Die
    # Tests ab 2026.10.18 setzen in ihren Repos `Test User` und vergleichen
    # darauf; Umgebungsvariablen gingen jeder Konfiguration vor (9 Tests rot,
    # 2026-10-25), die globale Datei nur dort, wo das Repo nichts setzt.
    preCheck = (alt.preCheck or "") + ''
      export GIT_CONFIG_GLOBAL="$TMPDIR/gitconfig-probe"
      printf '[user]\n\tname = probe\n\temail = probe@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
    '';
    disabledTests = (alt.disabledTests or [ ]) ++ [
      # Erwartet GitPythons Commit-Nachricht ohne Zeilenende ("add new"); der
      # Patch oben laesst `git commit` fahren, und Git schliesst jede Nachricht
      # mit "\n" ab. Genau die gewollte Abweichung.
      "test_git_commit_records_staged_changes"
      # Erwartet die Fehlermeldung mit `cmdline: git add …`; nixpkgs' gitpython
      # ruft git ueber den absoluten Store-Pfad auf.
      "test_git_add_nonexistent_file_is_git_error"
      # Erwartet das Verhalten von mcp >= 2.3 (kein leeres `experimental: {}`);
      # nixpkgs fuehrt 2.2.0, das diese Fassung ausdruecklich zulaesst.
      "test_initialize_reports_package_version_as_server_version"
      # Sucht das Konsolenskript neben sys.executable des Test-Pythons; im
      # Nix-Bau liegt es in $out/bin, nicht dort.
      "test_console_script_nonexistent_repository_exits_with_one_line_error"
    ];
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
