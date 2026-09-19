# lotse — Koordination der Parallelsitzungen auf dieser Workstation
# (github.com/achimcc/lotse). Hier laufen oft ein Dutzend Claude-Code-Sitzungen
# nebeneinander; eine NixOS-Auswertung wächst auf rund 12 GB, die Maschine hat
# 30. lotse stellt schwere Läufe an (Speicherbudget), wiederholt, was am Netz
# starb, und zeigt mit `lotse status`, wer gerade was tut.
#
# DREI TEILE, und alle drei gehören zusammen:
#
#  1. Das Binary SYSTEMWEIT — wie gestalt: Die Regel in ~/.claude/CLAUDE.md gilt
#     in jedem Projekt und darf nicht an einer geladenen devShell hängen.
#
#  2. Die Klassen für Repos OHNE eigene `lotse.toml`: ein Verweis auf die des
#     homeserver-Repos. Eine Quelle, keine zweite Kopie — wer dort einen
#     Schätzwert nachmisst, hat ihn damit überall nachgezogen. lotse sucht erst
#     vom Arbeitsverzeichnis aufwärts und nimmt diese Datei nur als Rückfall.
#
#  3. Der PreToolUse-Hook für Claude Code. Eine Regel in einer CLAUDE.md ist
#     etwas, woran man denken muss, und zwölf Sitzungen vergessen es zwölfmal.
#     Der Hook setzt `lotse run --class=… --` vor jedes Kommando einer Klasse mit
#     `wrap = true` — dort, wo die Shell es ausführen würde, und nirgends sonst.
#     Er gibt KEINE Freigabe: Das umgeschriebene Kommando läuft durch denselben
#     Freigabeweg wie jedes andere.
#
# WARUM EIN AKTIVIERUNGSSKRIPT UND KEIN SYMLINK: ~/.claude/settings.json
# schreibt Claude Code selbst (Modellwahl, Plugins). Als Link in den Store wäre
# sie schreibgeschützt, und `/model` schlüge fehl. Das Skript führt deshalb
# genau EINEN Eintrag nach — idempotent: Es entfernt jeden früheren
# lotse-Eintrag und hängt den aktuellen an, alles andere bleibt unberührt. Eine
# Datei, die kein gültiges JSON ist, fasst es nicht an.
{ pkgs, inputs, id, ... }:

let
  lotse = inputs.lotse.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # /run/current-system statt des Store-Pfads: Der bliebe nach einem Update in
  # der settings.json stehen, bis zur nächsten Aktivierung — und zeigte nach
  # einer Garbage Collection ins Leere.
  hook = builtins.toJSON {
    matcher = "Bash";
    hooks = [
      {
        type = "command";
        command = "/run/current-system/sw/bin/lotse hook claude";
        timeout = 10;
      }
    ];
  };
in
{
  environment.systemPackages = [ lotse ];

  home-manager.users.${id.username} =
    { lib, config, ... }:
    {
      xdg.configFile."lotse/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Projects/homeserver/lotse.toml";

      home.activation.claudeLotseHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson hook ${lib.escapeShellArg hook} '
              .hooks.PreToolUse = (
                ((.hooks.PreToolUse // [])
                  | map(select(
                      ((.hooks // []) | any((.command // "") | test("lotse hook claude"))) | not
                    )))
                + [$hook]
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "lotse: $datei ist kein gueltiges JSON — der Hook wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
