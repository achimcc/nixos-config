# savvy-progress + savvy-flow — Fortschrittsbalken ueber dem Prompt und ein
# Agenten-Panel (`/agents-info`) fuer Claude Code, dazu der Ablauf
# `/savvy-flow:savvy-flow`, der den Balken treibt
# (github.com/JohnnyVizz/claude-kit). 2026-10-12 auf Achims Wunsch.
#
# WARUM BEIDE: savvy-progress allein zeigt das Panel fuer JEDEN Subagenten
# (Modell, Kontext, geschaetzte Kosten, Zeit). Der BALKEN ueber dem Prompt
# erscheint aber erst, wenn jemand das Werkzeug `mcp__savvy-progress__progress`
# ruft oder ein Worker startet, dessen Typ mit `savvy-` beginnt — beides tut
# nur savvy-flow. Ohne den Skill bliebe der Balken leer.
#
# WARUM GEPINNT UND NICHT UEBER DEN MARKTPLATZ (anders als
# dem frueheren modules/claude-caveman.nix, B175): Ein Mod ist ein Hooks-Modul (`hooks/register.tsx`),
# das IM PROZESS von Claude Code laeuft und jeden Werkzeugaufruf und jede
# Modellantwort sieht. Der Marktplatz zoege jede neue Fassung eines fremden
# Repos ungesehen nach. Hier steht ein Rev mit Hash; die Fassung 272a877 ist
# gelesen (kein Netz, keine Shell, liest nur LC_ALL/LC_MESSAGES/LANG und die
# Einstellungen). Wer den Rev hebt, liest vorher den Diff von register.tsx.
# Dazu warnt das README selbst: Ein Mod aus dem Marktplatz erscheint nicht
# immer, der Weg ueber den Ordner ist der erprobte.
#
# WARUM EINE KOPIE UND NICHT DER STORE-PFAD: Die Engine schreibt beim Laden
# ihre Typen nach <mod>/.claude-plugin/types/ — im Store scheitert das (dieselbe
# Lehre wie modules/claude-werkbank.nix). Das Aktivierungsskript legt deshalb
# eine schreibbare Kopie unter ~/.local/share/claude-mods/ an und erneuert sie
# NUR, wenn sich der Store-Pfad geaendert hat — eine laufende Sitzung
# beobachtet den Ordner, ein Neuschreiben bei jedem Rebuild luede den Mod neu.
#
# Der Weg in Claude Code: `env.CLAUDE_CODE_PLUGIN_DIRS` in
# ~/.claude/settings.json, additiv wie bei werkbank. Ueber diesen Weg geladen
# heissen Skill und Agenten mit Namensraum: `/savvy-flow:savvy-flow`,
# `savvy-flow:savvy-careful` usw.
#
# EINSTELLUNG: `language` kennt nur auto/en/ru; `auto` faellt ohne Russisch
# ohnehin auf Englisch. Hier fest auf `en`, damit es nicht an LANG haengt.
#
# Die Engine dahinter (Function Hooks) ist Early Access; upstream getestet
# auf Claude Code 2.1.286. Bricht ein Update sie, fehlen Balken und Panel
# ohne Fehlermeldung.
{ pkgs, id, ... }:

let
  quelle = pkgs.fetchFromGitHub {
    owner = "JohnnyVizz";
    repo = "claude-kit";
    rev = "272a877f39b6971690e087b16a7cc3951b811e39";
    hash = "sha256-K+1MP18bP1NLkqQWu49IyKTbycng63sLdeLnMqDka/o=";
  };
  plugins = [
    "savvy-progress"
    "savvy-flow"
  ];
  sprache = "en";
in
{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      # DER BALKEN IN NORMALER ARBEIT (2026-10-12, Achims Entscheidung): Der
      # Skill savvy-flow traegt `disable-model-invocation: true`, ausserhalb von
      # `/savvy-flow:savvy-flow` riefe also niemand das Werkzeug. Diese Regel
      # laedt Claude Code als Nutzerregel in JEDER Sitzung (~/.claude/rules/),
      # und sie gehoert ganz diesem Modul — die handgepflegte
      # ~/.claude/CLAUDE.md bleibt unberuehrt.
      #
      # OHNE `tasks`: Der Mod oeffnet das Agenten-Panel von selbst, sobald
      # `tasks` mitkommt. Bei einem Dutzend Sitzungen ginge es staendig auf.
      # NUR DIE HAUPTSITZUNG: Der Zustand `flow` ist je Sitzung EINER; ein
      # Subagent, der meldet, ueberschriebe den Balken der Hauptsitzung.
      home.file.".claude/rules/savvy-fortschritt.md".text = ''
        # Fortschrittsbalken über dem Prompt

        Steht das Werkzeug `mcp__savvy-progress__progress` zur Verfügung — auch als
        deferred tool, dann zuerst mit ToolSearch laden
        (`select:mcp__savvy-progress__progress`) —, hält die Hauptsitzung damit den
        Balken über dem Prompt aktuell:

        - **Wann:** bei jeder Aufgabe mit drei oder mehr erkennbaren Schritten. Nicht
          bei einer kurzen Antwort, einer einzelnen Auskunft oder einem Handgriff.
        - **Beginn:** ein Aufruf mit `title` (wenige Wörter, deutsch), `total` (Zahl
          der Schritte), `done: 0`, `phase: "delegate"`. Solange noch erkundet wird
          und die Schritte nicht feststehen: nur `title` und `phase: "plan"`.
        - **Unterwegs:** nach jedem abgeschlossenen Schritt `done`. Ändert sich der
          Plan, das neue `total`. Der `title` bleibt über die ganze Aufgabe derselbe
          — ein neuer Titel setzt den Balken zurück.
        - **Ende:** `finished: true`, erst wenn das Ergebnis belegt ist.
        - **`tasks` nie mitgeben** — das öffnet das Agenten-Panel ungefragt.
        - **Nur die Hauptsitzung.** Wer als Subagent läuft, ruft `progress` nicht.
        - Läuft `/savvy-flow:savvy-flow`, gilt dessen Anleitung statt dieser.
        - Fehlt das Werkzeug: stillschweigend weglassen, nichts dazu sagen.

        Der Balken ist Anzeige, kein Bericht: kein Satz im Chat über den Aufruf.
      '';

      home.activation.claudeSavvyMods = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        basis="$HOME/.local/share/claude-mods"
        marke="$basis/claude-kit.quelle"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi

        veraltet=0
        if [ "$(${pkgs.coreutils}/bin/cat "$marke" 2>/dev/null || true)" != "${quelle}" ]; then
          veraltet=1
        fi
        for p in ${lib.escapeShellArgs plugins}; do
          if [ ! -e "$basis/$p/.claude-plugin/plugin.json" ]; then
            veraltet=1
          fi
        done
        if [ "$veraltet" = 1 ]; then
          run ${pkgs.coreutils}/bin/mkdir -p "$basis"
          for p in ${lib.escapeShellArgs plugins}; do
            run ${pkgs.coreutils}/bin/rm -rf "$basis/$p"
            run ${pkgs.coreutils}/bin/cp -r --no-preserve=mode,ownership "${quelle}/plugins/$p" "$basis/$p"
          done
          run sh -c 'printf "%s\n" "$1" > "$2"' _ "${quelle}" "$marke"
        fi

        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq \
              --arg basis "$basis" \
              --arg sprache ${lib.escapeShellArg sprache} \
              --argjson plugins ${lib.escapeShellArg (builtins.toJSON plugins)} '
              .env.CLAUDE_CODE_PLUGIN_DIRS = (
                ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(length > 0)))
                + ($plugins | map($basis + "/" + .)) | unique | join(":")
              )
              | .pluginConfigs["savvy-progress"].options.language = $sprache
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-savvy: $datei ist kein gueltiges JSON — die Eintraege wurden NICHT gesetzt." >&2
        fi
      '';
    };
}
