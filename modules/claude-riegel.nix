# Zwei kleine Hooks fuer Claude Code, die eine Regel aus Text zu einem
# Mechanismus machen (2026-09-28 auf Achims Wunsch).
#
#  1. `nix-parse` (PostToolUse auf Edit/Write/MultiEdit): Nach jeder
#     Aenderung an einer .nix-Datei `nix-instantiate --parse`. Das kostet
#     Millisekunden und faengt kaputte Syntax, bevor eine Serverauswertung
#     (12 GB, lotse-Warteschlange) daran scheitert. Exit 2 gibt die Meldung
#     an Claude zurueck; die Aenderung selbst ist schon geschrieben.
#     KEIN nixfmt: das homeserver-Repo ist nicht nixfmt-sauber, ein
#     Formatierer schriebe fremde Zeilen um.
#
#  2. `json-roh` (PreToolUse auf Bash): lehnt ein Kommando ab, dessen LETZTE
#     Pipe-Stufe `jq .` (bzw. `jq`, `jq -C .`, `python -m json.tool`) ist
#     und nicht in eine Datei umgeleitet wird. Das ist die Form, in der JSON
#     roh im Chat landet — und so sind schon zweimal echte Schluessel im Chat
#     gelandet. Der Weg ist `| gestalt` (CLAUDE.md). `jq -r '.feld'` bleibt
#     erlaubt: das ist Weiterverarbeitung, keine Ansicht.
#     GRENZE: Ein Muster, keine Semantik. `curl …` ohne jq zeigt JSON genauso
#     roh; das faengt dieser Riegel nicht, dafuer bleibt die Regel im Text.
#
# Eintrag in ~/.claude/settings.json wie bei lotse/caveat/hs-riegel: per
# Aktivierungsskript, idempotent, hinter `claudeHsRiegelHook`.
{ pkgs, id, ... }:

let
  # Eine Zeile, ein ERE. Als Datei, damit kein Shell-Quoting dazwischenfunkt.
  # Trifft `jq`, `jq .`, `jq -C '.'`, `jq -S . datei.json` und
  # `python -m json.tool [< datei]` — nicht `jq .feld`, `jq -r …`, `jq '.[]'`.
  rohMuster = pkgs.writeText "json-roh.ere" ''
    ^(jq([[:space:]]+-[CSMcas]+)*([[:space:]]+(\.|'\.'|"\."))?([[:space:]]+[^[:space:].'"-][^[:space:]]*)*|python3?[[:space:]]+-m[[:space:]]+json\.tool)([[:space:]]*<[[:space:]]*[^[:space:]]+)?[[:space:]]*$
  '';

  riegel = pkgs.writeShellApplication {
    name = "claude-riegel";
    runtimeInputs = [ pkgs.jq pkgs.nix pkgs.gnugrep ];
    text = ''
      eingabe=$(cat)
      case "''${1:-}" in
        nix-parse)
          datei=$(jq -r '.tool_input.file_path // empty' <<<"$eingabe")
          case "$datei" in
            *.nix) ;;
            *) exit 0 ;;
          esac
          [ -f "$datei" ] || exit 0
          if ! fehler=$(nix-instantiate --parse "$datei" 2>&1 >/dev/null); then
            printf 'nix-parse: %s parst nicht:\n%s\n' "$datei" "$fehler" >&2
            exit 2
          fi
          ;;
        json-roh)
          cmd=$(jq -r '.tool_input.command // empty' <<<"$eingabe")
          # letzte Pipe-Stufe, fuehrende Leerzeichen weg
          letzte=''${cmd##*|}
          letzte=''${letzte#"''${letzte%%[![:space:]]*}"}
          case "$letzte" in
            *'>'*) exit 0 ;;
          esac
          if grep -Eqf ${rohMuster} <<<"$letzte"; then
            jq -n --arg grund "json-roh: JSON nie roh in den Chat — statt '$letzte' '| gestalt' (Form), dann 'gestalt -s <pfad>' fuer genau die Felder. Siehe CLAUDE.md, Abschnitt Geheimnisse." \
              '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $grund}}'
          fi
          ;;
        *)
          echo "Aufruf: claude-riegel nix-parse|json-roh (JSON des Hooks auf stdin)" >&2
          exit 2
          ;;
      esac
    '';
  };

  nixParse = builtins.toJSON {
    matcher = "Edit|Write|MultiEdit";
    hooks = [
      {
        type = "command";
        command = "/run/current-system/sw/bin/claude-riegel nix-parse";
        timeout = 10;
      }
    ];
  };
  jsonRoh = builtins.toJSON {
    matcher = "Bash";
    hooks = [
      {
        type = "command";
        command = "/run/current-system/sw/bin/claude-riegel json-roh";
        timeout = 5;
      }
    ];
  };
in
{
  environment.systemPackages = [ riegel ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeRiegelHooks = lib.hm.dag.entryAfter [ "claudeHsRiegelHook" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson parse ${lib.escapeShellArg nixParse} --argjson roh ${lib.escapeShellArg jsonRoh} '
              def ohne($e; $muster): ((.hooks[$e] // [])
                | map(select(((.hooks // []) | any((.command // "") | test($muster))) | not)));
              .hooks.PostToolUse = (ohne("PostToolUse"; "claude-riegel nix-parse") + [$parse])
              | .hooks.PreToolUse = (ohne("PreToolUse"; "claude-riegel json-roh") + [$roh])
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-riegel: $datei ist kein gueltiges JSON — die Hooks wurden NICHT eingetragen." >&2
        fi
      '';
    };
}
