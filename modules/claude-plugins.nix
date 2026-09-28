# Offizielle Claude-Code-Plugins aus Anthropics Marktplatz
# (`claude-plugins-official`), deklarativ eingeschaltet.
#
# Dieselbe Bauart wie modules/claude-obsidian.nix: ~/.claude/settings.json
# schreibt Claude Code selbst (Modellwahl, Plugin-Schalter) und darf deshalb
# kein Link in den Store sein. Das Aktivierungsskript setzt nur
# `.enabledPlugins["<name>@claude-plugins-official"] = true` fuer jeden Namen
# der Liste — idempotent, alles andere bleibt unberuehrt, und eine Datei, die
# kein gueltiges JSON ist, fasst es nicht an.
#
# Den Plugin-CODE holt Claude Code selbst aus dem Marktplatz und haelt ihn
# aktuell. Diese Datei legt fest, WELCHE Plugins an sind, nicht welche Fassung.
#
# Der Marktplatz selbst ist in Claude Code eingebaut und braucht keinen
# `extraKnownMarketplaces`-Eintrag.
#
# frontend-design: Anthropics Skill fuer die Gestaltung von Oberflaechen
# (2026-09-22 auf Achims Wunsch).
#
# feature-dev: Anthropics Arbeitsablauf fuer neue Features (Erkunden,
# Architektur, Review ueber eigene Agenten) — 2026-09-26 auf Achims Wunsch.
#
# code-review: Anthropics PR-Review mit mehreren Agenten — 2026-09-26 auf
# Achims Wunsch. Nicht zu verwechseln mit dem eingebauten `/code-review`
# von Claude Code; das Plugin meldet sich unter seinem Namensraum.
#
# chrome-devtools-mcp: Googles MCP-Server fuer Chrome DevTools (Seiten
# steuern, Netzwerk, Konsole, Performance, Lighthouse) samt Skills —
# 2026-09-28 auf Achims Wunsch. War vorher nur von Hand eingeschaltet. Der
# Server startet ueber `npx` und steuert das systemweite google-chrome-stable.
{ pkgs, id, ... }:

let
  plugins = [
    "frontend-design"
    "feature-dev"
    "code-review"
    "chrome-devtools-mcp"
  ];
  filter = builtins.concatStringsSep " | " (
    map (p: ''.enabledPlugins["${p}@claude-plugins-official"] = true'') plugins
  );
in
{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeOfficialPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq ${lib.escapeShellArg filter} "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-plugins: $datei ist kein gueltiges JSON — die Eintraege wurden NICHT gesetzt." >&2
        fi
      '';
    };
}
