# graphify — macht aus einem Ordner (Code, Doku, Schemata) einen abfragbaren
# Wissensgraphen (github.com/Graphify-Labs/graphify). 2026-10-09 auf Achims
# Wunsch, global fuer alle Repos.
#
# KEIN MARKTPLATZ-PLUGIN, und deshalb eine andere Bauart als
# modules/claude-obsidian.nix: Das Projekt hat kein `.claude-plugin/`, also
# gibt es nichts fuer `extraKnownMarketplaces` und `enabledPlugins`. Es besteht
# aus ZWEI Teilen, und der Skill ohne das Programm tut nichts:
#
#  1. Das Programm `graphify` (PyPI: `graphifyy`, in nixpkgs als `graphify`).
#     Der Skill ruft es ueber den PATH auf — darum systemweit, wie gestalt.
#
#  2. Der Skill unter ~/.claude/skills/graphify/ (SKILL.md, references/,
#     .graphify_version). Upstream legt ihn mit `graphify install` an. Hier
#     laeuft derselbe Installer zur BAUZEIT in einem Wegwerf-HOME, und das
#     Aktivierungsskript kopiert das Ergebnis. So stammt der Skill immer aus
#     der Fassung des Programms, das im PATH steht — ein nixpkgs-Update zieht
#     beide zusammen nach, und niemand muss `graphify install` von Hand fahren.
#
# WARUM KOPIE UND KEIN LINK IN DEN STORE: Der Skill schreibt selbst nichts in
# sein Verzeichnis, aber `graphify install` (falls es doch jemand faehrt)
# ersetzt references/ atomar und scheiterte an einem schreibgeschuetzten Ziel.
# Das Verzeichnis gehoert trotzdem DIESER Datei: Die Aktivierung ersetzt es
# ganz, eine Handaenderung darin ueberlebt den naechsten Rebuild nicht.
#
# WAS HIER BEWUSST NICHT STEHT:
#  - Der Abschnitt „# graphify" in ~/.claude/CLAUDE.md, den der Installer
#    anhaengt. Die Datei ist von Hand geschrieben, und Claude Code findet einen
#    Skill unter ~/.claude/skills ohne diesen Verweis.
#  - Die PreToolUse-Hooks („erst graphify query, dann grep"). Die setzt nur
#    die PROJEKT-Installation (`graphify claude install`, schreibt in
#    .claude/settings.json und CLAUDE.md des Repos); der globale Weg kennt sie
#    nicht. Wer sie in einem Repo will, entscheidet das dort.
#  - Der MCP-Server (`graphify-mcp`) — liegt im Paket, ist aber nicht
#    eingetragen.
{ pkgs, id, ... }:

let
  skill = pkgs.runCommand "graphify-claude-skill-${pkgs.graphify.version}" { } ''
    export HOME="$TMPDIR/heim"
    mkdir -p "$HOME"
    ${pkgs.graphify}/bin/graphify install > /dev/null
    test -s "$HOME/.claude/skills/graphify/SKILL.md"
    cp -r "$HOME/.claude/skills/graphify" "$out"
  '';
in
{
  environment.systemPackages = [ pkgs.graphify ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeGraphifySkill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ziel="$HOME/.claude/skills/graphify"
        run mkdir -p "$HOME/.claude/skills"
        run rm -rf "$ziel"
        run cp -r --no-preserve=mode ${skill} "$ziel"
      '';
    };
}
