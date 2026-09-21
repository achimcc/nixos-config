# caveat — die Lehre in dem Moment, in dem man sie braucht
# (github.com/achimcc/caveat, Entwurf im homeserver-Repo:
# docs/2026-09-21-caveat-design.md).
#
# DREI TEILE, wie bei lotse.nix:
#
#  1. Das Binary SYSTEMWEIT — der Hook gilt in jedem Projekt und darf nicht an
#     einer geladenen devShell haengen.
#
#  2. Der Rueckfall fuer Repos OHNE eigenes `caveats/`: ein Verweis auf das des
#     homeserver-Repos. Viele Fallen sind nicht repo-spezifisch (die
#     VPS-Aussperrung, `grep -q` unter pipefail). caveat sucht erst vom
#     Arbeitsverzeichnis aufwaerts — ein Worktree bringt seine eigene Fassung
#     mit — und nimmt diese Datei nur als Rueckfall.
#
#  3. DREI Hook-Eintraege fuer Claude Code: PreToolUse (das Kommando),
#     PostToolUse (die Ausgabe eines gelungenen Laufs) und PostToolUseFailure
#     (die eines gescheiterten — und gerade dort stehen die Meldungen). Der
#     Hook gibt KEINE Freigabe und schreibt NIE ein Kommando um: Mehrere
#     PreToolUse-Hooks laufen parallel, von mehreren `updatedInput` gewinnt
#     zufaellig eines, und diesen Platz braucht lotse.
#
# WARUM EIN AKTIVIERUNGSSKRIPT UND KEIN SYMLINK: s. lotse.nix —
# ~/.claude/settings.json schreibt Claude Code selbst. Das Skript fuehrt genau
# seine drei Eintraege nach, idempotent, und fasst eine Datei, die kein
# gueltiges JSON ist, nicht an.
#
# REIHENFOLGE GEGENUEBER DEN ANDEREN SCHREIBERN DERSELBEN DATEI: Es gibt genau
# zwei, `claudeLotseHook` (modules/lotse.nix) und `claudeObsidianPlugin`
# (modules/claude-obsidian.nix) — modules/mcp-nixos.nix schreibt trotz seines
# Kommentars zu ~/.claude/settings.json tatsaechlich in die ANDERE Datei,
# ~/.claude.json, und faellt damit weg. `claudeCaveatHook` haengt hier nur
# hinter `claudeLotseHook`: Beide schreiben in denselben Zweig `.hooks.*`,
# lotse nach `.hooks.PreToolUse`, caveat nach allen drei Ereignissen — ohne
# Reihenfolge koennte der zuletzt gelesene Stand des einen den frisch
# geschriebenen Eintrag des anderen wieder verlieren. `claudeObsidianPlugin`
# schreibt disjunkte Schluessel (`.extraKnownMarketplaces`,
# `.enabledPlugins`) und braucht deshalb KEINEN Platz in dieser Kette: Home
# Managers Aktivierung ist ein EINZIGES, sequentielles Bash-Skript
# (`activationScript` in home-environment.nix, `pkgs.writeShellScript` ueber
# die DAG-sortierten Eintraege) — zwei Eintraege laufen dort nie wirklich
# GLEICHZEITIG, jeder liest die Datei neu von der Platte, bevor er schreibt.
# Ein voneinander unabhaengiger, aber sequentieller Lauf verliert also auch
# ohne deklarierte Reihenfolge nichts, solange die Schluessel disjunkt sind.
{ pkgs, inputs, id, ... }:

let
  caveat = inputs.caveat.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # /run/current-system statt des Store-Pfads, aus demselben Grund wie bei lotse.
  hook = builtins.toJSON {
    matcher = "Bash";
    hooks = [
      {
        type = "command";
        command = "/run/current-system/sw/bin/caveat hook claude";
        timeout = 5;
      }
    ];
  };
in
{
  environment.systemPackages = [ caveat ];

  home-manager.users.${id.username} =
    { lib, config, ... }:
    {
      xdg.configFile."caveat/config.toml".text = ''
        dir = "${config.home.homeDirectory}/Projects/homeserver/caveats"
      '';

      # NACH dem lotse-Eintrag, damit beide Skripte nicht dieselbe Datei
      # gleichzeitig umschreiben.
      home.activation.claudeCaveatHook = lib.hm.dag.entryAfter [ "claudeLotseHook" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson hook ${lib.escapeShellArg hook} '
              reduce ("PreToolUse", "PostToolUse", "PostToolUseFailure") as $e (.;
                .hooks[$e] = (
                  ((.hooks[$e] // [])
                    | map(select(
                        ((.hooks // []) | any((.command // "") | test("caveat hook claude"))) | not
                      )))
                  + [$hook]
                )
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "caveat: $datei ist kein gueltiges JSON — die Hooks wurden NICHT eingetragen." >&2
        fi
      '';
    };
}
