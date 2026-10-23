# werkbank — eigener Claude-Code-Mod (mods/werkbank): `/laufend` zeigt die
# Hintergrundarbeit, `/fertig` prueft den Abschluss, `/uebergabe` reicht an
# einen frischen Agenten weiter. 2026-10-11.
#
# WARUM ES DIESE DATEI GIBT: Ein Mod, den eine Sitzung schreibt, liegt unter
# ~/.claude/dev-mods/<Sitzungs-ID>/ und laedt NUR in dieser einen Sitzung.
# Jede andere kannte die drei Kommandos nicht — ohne Fehlermeldung, sie
# fehlten einfach in der Liste.
#
# Der Weg: `env.CLAUDE_CODE_PLUGIN_DIRS` in ~/.claude/settings.json. Claude
# Code liest die Variable aus dem `env`-Block der NUTZER-Einstellungen und
# laedt jeden genannten Ordner wie ein `--plugin-dir`. Dieselbe Bauart wie
# modules/claude-obsidian.nix: Das Aktivierungsskript setzt genau einen
# Schluessel, idempotent; fremde Ordner in der Liste bleiben stehen, und eine
# Datei, die kein gueltiges JSON ist, fasst es nicht an.
#
# WARUM DER ARBEITSBAUM UND NICHT DER STORE: Die Engine schreibt beim Laden
# ihre Typen nach <mod>/.claude-plugin/types/ (in .gitignore) — im Store
# scheiterte das. Und eine interaktive Sitzung beobachtet den Ordner: Eine
# gespeicherte Aenderung an mods/werkbank wirkt ohne Rebuild. Der Preis: Was
# laeuft, ist der Arbeitsbaum, nicht der letzte Commit.
{ pkgs, id, ... }:

{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeWerkbankMod = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        ordner="$HOME/nixos-config/mods/werkbank"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        if [ ! -e "$ordner/.claude-plugin/plugin.json" ]; then
          echo "claude-werkbank: $ordner fehlt — die Kommandos laden nicht." >&2
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --arg ordner "$ordner" '
              .env.CLAUDE_CODE_PLUGIN_DIRS = (
                ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(length > 0)))
                + [ $ordner ] | unique | join(":")
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-werkbank: $datei ist kein gueltiges JSON — der Eintrag wurde NICHT gesetzt." >&2
        fi
      '';
    };
}
