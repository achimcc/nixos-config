# Claude-Code-Plugins: WELCHE an sind, welche aus, und welche ganz weg.
#
# SEIT AUDIT 4 (2026-10-15, B174/B175/B231-B238, Empfehlung E-2/E-7) ist das
# hier die EINE Liste. Bis dahin waren 6 von 23 eingeschalteten Plugins
# deklariert; die uebrigen 17 und zwei Marktplaetze standen nur in
# ~/.claude/settings.json, kein Rebuild stellte sie her oder nahm sie weg, und
# kein Review sah ihr Kommen (B232). Jetzt gilt:
#
#  - `an`: offizielle Plugins (Marktplatz `claude-plugins-official`), die
#    eingeschaltet sind. JEDER eingeschaltete Name steht hier.
#  - Jeder ANDERE Schluessel in `enabledPlugins` wird bei jedem Rebuild auf
#    false gesetzt (ausser den eingebauten `…@builtin`). Wer in einer Sitzung
#    `/plugin enable` tippt, bekommt es bis zum naechsten Rebuild — danach
#    gilt wieder diese Datei. Auf Abruf (`/plugin enable <name>`) bleiben
#    installiert, aber aus: context7 und chrome-devtools-mcp (`aufAbruf`).
#  - `entfernen`: Plugins, die DEINSTALLIERT werden — Eintrag aus
#    enabledPlugins und installed_plugins.json, Cache-Ordner weg.
#  - `marktplaetzeWeg`: Marktplaetze von Dritten, die ganz verschwinden —
#    aus extraKnownMarketplaces, known_marketplaces.json und der Klon unter
#    ~/.claude/plugins/marketplaces/. Ohne Marktplatz kann `/plugin` keine
#    neue, ungepinnte Fassung mehr daneben ziehen (B174).
#
# Was von Dritten bleibt, laeuft GEPINNT ausserhalb des Marktplatzes:
# claude-obsidian (modules/claude-obsidian.nix, Rev und Hash), savvy
# (modules/claude-savvy.nix), werkbank (eigen), graphify (nixpkgs) und die
# acht gebrauchten secskills als eigene Kopie (modules/claude-skills.nix, B235).
#
# Die offiziellen Plugins holt Claude Code weiter selbst aus Anthropics
# Marktplatz und haelt sie aktuell; deren Review und Pins auf externe Repos
# gelten als Schranke (PL.md §4). Der Marktplatz ist eingebaut und braucht
# keinen `extraKnownMarketplaces`-Eintrag.
#
# Bauart wie modules/claude-obsidian.nix: ~/.claude/settings.json schreibt
# Claude Code selbst und darf kein Link in den Store sein. Jede JSON-Datei wird
# nur angefasst, wenn sie gueltiges JSON ist, und atomar ersetzt.
#
# WARUM WELCHES PLUGIN WEG IST (Zahlen aus PL.md, 30 Tage, 353 Hauptsitzungen):
#  - caveman (B175, B238): 0 Nutzung, Regeltext per SessionStart in 165
#    Sitzungen, `caveman-init` liess das Modell `curl … /main/… | node -`
#    ausfuehren, `caveman-setup` leitete LLM-Verkehr ueber ein fremdes Gateway.
#    Frueher modules/claude-caveman.nix (2026-09-26), jetzt geloescht.
#  - explanatory-output-style (B238): SessionStart-Text in 43 Sitzungen,
#    widerspricht CLAUDE.md; 0 messbarer Nutzen.
#  - claude-mem-cowork@thedotmack (B231): war schon aus, haette gekoppelt
#    tool_input/tool_response JEDES Aufrufs an cmem.ai geschickt. Ein `true`
#    haette gereicht — darum deinstalliert und Marktplatz weg.
#  - hookify (B237): vier Python-Hooks auf jedem Aufruf ohne eine Regel; liest
#    Regeln aus dem Arbeitsverzeichnis. Ersatz: claude-regeln (claude-riegel.nix).
#  - fp-check und die uebrigen fuenf trailofbits-Plugins (B236): befristet fuer
#    Audit 4; fp-check lief als Prompt-Hook nach JEDER Antwort jeder Sitzung.
#    Das Audit ist vorbei.
#  - code-review, code-simplifier, commit-commands: 0 Nutzung; das eingebaute
#    `/code-review` deckt das Review ab, Commits laufen ueber eigene Riegel.
#  - github@claude-plugins-official: brauchte GITHUB_PERSONAL_ACCESS_TOKEN in
#    der Umgebung; Ersatz modules/mcp-github.nix (nur lesend, Token aus sops).
#  - secskills-core (B235, E-7): 10 von 30 Skills wiesen an, URLs ueber
#    defuddle.md zu holen; gebraucht wurden 8 — die liegen jetzt als eigene
#    Kopie ohne diese Zeile unter modules/claude-skills/secskills/.
#  - claude-obsidian@agricidaniel-claude-obsidian (B174): nicht weg, sondern
#    gepinnt — die Marktplatz-Fassung wird durch die aus
#    modules/claude-obsidian.nix ersetzt.
#
# AUF ABRUF statt dauernd an:
#  - context7 (B234): entfernter HTTP-MCP, dessen Werkzeugtexte zur Laufzeit
#    vom Anbieter kommen und dessen Anfragen das Haus verlassen. Bei Bedarf
#    `/plugin enable context7@claude-plugins-official`, und dann keine Haus-,
#    Gast- oder Repo-Namen in Anfragen.
#  - chrome-devtools-mcp (B172): startet ueber `npx` Code aus npm an Nix vorbei
#    und meldete Nutzungsdaten an Google. Nicht in nixpkgs; ein eigenes
#    Nix-Paket braucht einen Bau (npm-Hash), den diese Abhilfe nicht faehrt.
#    Bis dahin aus; fuer Browser-Arbeit steht der Playwright-MCP bereit
#    (modules/mcp-playwright.nix). Die Telemetrie ist systemweit abgeschaltet,
#    falls es doch jemand einschaltet.
#
# security-guidance (B233): Sein SessionStart-Hook legte `claude-agent-sdk`
# ohne Version und Hash per pip in ~/.claude/security/agent-sdk-venv an. Er
# tut das nur, wenn das SDK im System-python3 FEHLT — configuration.nix
# fuehrt python3 deshalb mit dem SDK aus nixpkgs. Die pip-Fassung wird hier
# geloescht, sobald das System-SDK importierbar ist (sonst laege sie vorn im
# sys.path des Hooks).
{ pkgs, id, ... }:

let
  an = [
    "rust-analyzer-lsp"
    "superpowers"
    "claude-code-setup"
    "claude-md-management"
    "frontend-design" # 2026-09-22 auf Achims Wunsch
    "feature-dev" # 2026-09-26 auf Achims Wunsch
    "security-guidance"
  ];

  # Installiert, aber ausdruecklich aus — bei Bedarf `/plugin enable` (B172, B234).
  aufAbruf = [
    "context7@claude-plugins-official"
    "chrome-devtools-mcp@claude-plugins-official"
  ];

  # Deinstallieren: <plugin>@<marktplatz> (B175, B231, B235-B238, E-2).
  entfernen = [
    "caveman@caveman"
    "claude-mem-cowork@thedotmack"
    "github@claude-plugins-official"
    "explanatory-output-style@claude-plugins-official"
    "hookify@claude-plugins-official"
    "code-review@claude-plugins-official"
    "code-simplifier@claude-plugins-official"
    "commit-commands@claude-plugins-official"
    "fp-check@trailofbits"
    "rust-review@trailofbits"
    "differential-review@trailofbits"
    "insecure-defaults@trailofbits"
    "sharp-edges@trailofbits"
    "agentic-actions-auditor@trailofbits"
    "secskills-core@secskills-marketplace"
    "claude-obsidian@agricidaniel-claude-obsidian"
  ];

  # Marktplaetze von Dritten, die ganz verschwinden (E-2: 6 -> 0).
  marktplaetzeWeg = [
    "caveman"
    "thedotmack"
    "trailofbits"
    "secskills-marketplace"
    "agricidaniel-claude-obsidian"
    "superpowers-marketplace"
  ];

  anVoll = map (p: "${p}@claude-plugins-official") an;

  # Dieselbe Ableitung wie in configuration.nix (B233) — gleiche Eingaben,
  # gleiche Ableitung; hier nur fuer die Probe, ob das SDK importierbar ist.
  pythonMitSdk = pkgs.python3.withPackages (p: [ p.claude-agent-sdk ]);

  json = builtins.toJSON;
in
{
  # B172: chrome-devtools-mcp meldet sonst Werkzeugname, Erfolg, Latenz und
  # Umgebung an play.googleapis.com — auch wenn es nur auf Abruf laeuft.
  environment.sessionVariables.CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS = "1";

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeOfficialPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        jq=${pkgs.jq}/bin/jq
        mktemp=${pkgs.coreutils}/bin/mktemp
        # <datei> <jq-programm> [jq-argumente…] — nur gueltiges JSON, atomar.
        json_setzen() {
          local datei=$1 programm=$2
          shift 2
          [ -e "$datei" ] || return 0
          local neu
          neu="$($mktemp "$datei.XXXXXX")"
          if $jq "$@" "$programm" "$datei" > "$neu"; then
            run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
            run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
          else
            ${pkgs.coreutils}/bin/rm -f "$neu"
            echo "claude-plugins: $datei ist kein gueltiges JSON — NICHT geaendert." >&2
          fi
        }

        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi

        # B232: an -> true, entfernen -> Schluessel weg, alles andere (ausser
        # @builtin) -> false; Marktplaetze von Dritten aus der Liste.
        json_setzen "$datei" '
          .enabledPlugins = (
            (.enabledPlugins // {})
            | with_entries(select(.key as $k | $weg | index($k) | not))
            | with_entries(
                if (.key | endswith("@builtin")) then .
                elif (.key as $k | $an | index($k)) then .value = true
                else .value = false end)
            | . + ($ab | map({ key: ., value: false }) | from_entries)
            | . + ($an | map({ key: ., value: true }) | from_entries)
          )
          | .extraKnownMarketplaces = (
              (.extraKnownMarketplaces // {})
              | with_entries(select(.key as $k | $mweg | index($k) | not))
            )
        ' --argjson an ${lib.escapeShellArg (json anVoll)} \
          --argjson ab ${lib.escapeShellArg (json aufAbruf)} \
          --argjson weg ${lib.escapeShellArg (json entfernen)} \
          --argjson mweg ${lib.escapeShellArg (json marktplaetzeWeg)}

        plugins="$HOME/.claude/plugins"
        # Deinstallieren: Eintrag aus installed_plugins.json, Cache-Ordner weg.
        json_setzen "$plugins/installed_plugins.json" '
          .plugins = ((.plugins // {}) | with_entries(select(.key as $k | $weg | index($k) | not)))
        ' --argjson weg ${lib.escapeShellArg (json entfernen)}
        for p in ${lib.escapeShellArgs entfernen}; do
          name=''${p%@*}
          markt=''${p#*@}
          if [ -e "$plugins/cache/$markt/$name" ]; then
            run ${pkgs.coreutils}/bin/rm -rf "$plugins/cache/$markt/$name"
          fi
        done
        # Marktplaetze: Eintrag, Klon und Cache weg.
        json_setzen "$plugins/known_marketplaces.json" '
          with_entries(select(.key as $k | $mweg | index($k) | not))
        ' --argjson mweg ${lib.escapeShellArg (json marktplaetzeWeg)}
        for m in ${lib.escapeShellArgs marktplaetzeWeg}; do
          for o in "$plugins/marketplaces/$m" "$plugins/cache/$m"; do
            if [ -e "$o" ]; then
              run ${pkgs.coreutils}/bin/rm -rf "$o"
            fi
          done
        done

        # B175: was caveman ausserhalb seines Plugin-Ordners hinterliess.
        for o in "$HOME/.claude/.caveman-active" "$HOME/.claude/.caveman-mode-log.jsonl" \
                 "$HOME/.claude/.caveman-sessions" "$HOME/.config/caveman"; do
          if [ -e "$o" ]; then
            run ${pkgs.coreutils}/bin/rm -rf "$o"
          fi
        done

        # B233: die pip-Fassung des Agent-SDK weg, sobald das System-SDK
        # (nixpkgs) importierbar ist — sonst stuende sie vorn im sys.path.
        sicher="$HOME/.claude/security"
        if ${pythonMitSdk}/bin/python3 -c 'import claude_agent_sdk' 2>/dev/null; then
          for o in "$sicher/agent-sdk-venv" "$sicher/agent-sdk-libs" "$sicher/agent-sdk-venv.cooldown"; do
            if [ -e "$o" ]; then
              run ${pkgs.coreutils}/bin/rm -rf "$o"
            fi
          done
        else
          echo "claude-plugins: claude_agent_sdk im System-python3 nicht importierbar — pip-Fassung bleibt (B233)." >&2
        fi
      '';
    };
}
