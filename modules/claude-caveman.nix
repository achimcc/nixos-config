# caveman — Claude-Code-Plugin, das Antworten auf knappe Stichpunktsprache
# kuerzt und damit Ausgabe-Token spart (github.com/JuliusBrussee/caveman).
# 2026-09-26 auf Achims Wunsch.
#
# Dieselbe Bauart wie modules/claude-obsidian.nix: Das Projekt bringt seinen
# eigenen Marktplatz mit (`.claude-plugin/marketplace.json`, Name `caveman`,
# Plugin `caveman`). Das Aktivierungsskript setzt genau zwei Schluessel in
# ~/.claude/settings.json — `extraKnownMarketplaces.caveman` und
# `enabledPlugins["caveman@caveman"]` —, idempotent; alles andere bleibt
# unberuehrt, und eine Datei, die kein gueltiges JSON ist, fasst es nicht an.
#
# Den Plugin-CODE holt Claude Code selbst von GitHub und haelt ihn aktuell.
# Diese Datei legt fest, DASS es an ist, nicht welche Fassung.
{ pkgs, id, ... }:

let
  marktplatz = builtins.toJSON {
    source = {
      source = "github";
      repo = "JuliusBrussee/caveman";
    };
  };
in
{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeCavemanPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson markt ${lib.escapeShellArg marktplatz} '
              .extraKnownMarketplaces["caveman"] = $markt
              | .enabledPlugins["caveman@caveman"] = true
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-caveman: $datei ist kein gueltiges JSON — der Eintrag wurde NICHT gesetzt." >&2
        fi
      '';
    };
}
