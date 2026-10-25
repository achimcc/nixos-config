# context-diet — kuerzt grosse Werkzeugausgaben (Logs, JSON, Diffs, grep,
# Dateilisten), bevor sie in den Kontext gelangen; die volle Ausgabe liegt
# danach unter <projekt>/.context-diet/ zum Nachlesen
# (github.com/drkokorev/context-diet, Unterordner plugins/context-diet).
#
# Bis 2026-10-25 von Hand aus dem Marktplatz `context-diet` installiert; den
# raeumt modules/claude-plugins.nix jetzt ab (`entfernen`, `marktplaetzeWeg`),
# und ohne diesen Eintrag schaltete jeder Rebuild das Plugin aus (B232).
# Bauart wie modules/claude-savvy.nix: gepinnt, schreibbare Kopie unter
# ~/.local/share/claude-mods/, eingebunden ueber CLAUDE_CODE_PLUGIN_DIRS.
#
# GELESEN 2026-10-25 (0.3.0, Rev 1988532; der Unterordner ist gleich dem bis
# dahin installierten Marktplatz-Cache). MIT, Einzelpfleger, Repo zwei Wochen
# alt — darum gepinnt und vor jedem Heben den Diff lesen. Kein Hook-Skript,
# sondern ein Modul im Claude-Code-Prozess (Mod-API `claude-code`, wie savvy):
# kein Netz, kein Prozessstart, schreibt nur unter <projekt>/.context-diet/
# (legt dort selbst eine .gitignore mit `*` an). Die Option `capture`, die
# Bash-Befehle umschreibt, um ihre Ausgabe mitzuschneiden, ist ab Werk AUS.
#
# WAS MAN WISSEN MUSS: Unter .context-diet/ liegt die VOLLE Ausgabe jedes
# gekuerzten Aufrufs — also auch ein Geheimnis, das dort durchlief. Die Datei
# verlaesst die Maschine nicht und kommt nicht in Git, liegt aber im
# Arbeitsbaum, bis jemand sie loescht.
{ pkgs, id, ... }:

let
  quelle = pkgs.fetchFromGitHub {
    owner = "drkokorev";
    repo = "context-diet";
    rev = "1988532e2951200644b9ae793f47f12092d3cca6";
    hash = "sha256-PfWGNx+G6cOO8nBRYMyTZZNneSI6c8ikFyfAHo187pY=";
  };
in
{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      # Nach claudeOfficialPlugins, das den alten Marktplatz-Eintrag abraeumt.
      home.activation.claudeContextDiet = lib.hm.dag.entryAfter [ "writeBoundary" "claudeOfficialPlugins" ] ''
        datei="$HOME/.claude/settings.json"
        basis="$HOME/.local/share/claude-mods"
        ziel="$basis/context-diet"
        marke="$basis/context-diet.quelle"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        if [ "$(${pkgs.coreutils}/bin/cat "$marke" 2>/dev/null || true)" != "${quelle}" ] \
          || [ ! -e "$ziel/.claude-plugin/plugin.json" ]; then
          run ${pkgs.coreutils}/bin/mkdir -p "$basis"
          run ${pkgs.coreutils}/bin/rm -rf "$ziel"
          run ${pkgs.coreutils}/bin/cp -r --no-preserve=mode,ownership "${quelle}/plugins/context-diet" "$ziel"
          run sh -c 'printf "%s\n" "$1" > "$2"' _ "${quelle}" "$marke"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --arg ziel "$ziel" '
              .env.CLAUDE_CODE_PLUGIN_DIRS = (
                ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(length > 0)))
                + [ $ziel ] | unique | join(":")
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "context-diet: $datei ist kein gueltiges JSON — der Eintrag wurde NICHT gesetzt." >&2
        fi
      '';
    };
}
