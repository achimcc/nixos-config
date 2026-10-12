"""claude-regeln: Muster-Regeln fuer Claude Code, als Hook und als Pruefung.

  claude-regeln hook                 JSON des Hooks auf stdin (PreToolUse/Bash,
                                     UserPromptSubmit), Antwort auf stdout
  claude-regeln pruefen <dir> <json> jede Regel in <dir> gegen ihre Faelle

Eine Regel ist eine Markdown-Datei: Kopf zwischen zwei `---`-Zeilen mit
`name`, `event` (bash|prompt), `pattern` (EINE Zeile, Python-Regex, ohne
Beachtung der Gross-/Kleinschreibung), `action` (warn|block), optional
`enabled: false`. Der Rest ist die Meldung an Claude.

Quellen: die globalen Regeln aus dem Nix-Store (CLAUDE_REGELN_GLOBAL) und die
des Projekts unter `.claude/riegel/*.md` - gesucht vom Arbeitsverzeichnis der
Sitzung aufwaerts, damit ein Worktree seine eigene Fassung hat und ein
aelterer Worktree die des Hauptbaums erbt.

Warum nicht hookify (gemessen 2026-10-12, Stand f359d43b4060): `warn` geht
dort nur als systemMessage hinaus und erreicht das Modell nicht, `block`
traegt keinen Grund, und Prompt-Regeln lesen das Feld `user_prompt`, das
Claude Code nicht liefert.
"""

import glob
import json
import os
import re
import sys
import time

# Eine Warnung wird je Sitzung und Regel hoechstens einmal in dieser Spanne
# gezeigt: 2076 sleep-Aufrufe in 172 Sitzungen waeren sonst 2076 Meldungen.
RUHE_SEKUNDEN = 30 * 60


class Regel:
    def __init__(self, pfad):
        text = open(pfad, encoding="utf-8").read()
        teile = text.split("---", 2)
        if not text.startswith("---") or len(teile) < 3:
            raise ValueError(f"{pfad}: kein Kopf zwischen zwei ---")
        kopf = {}
        for zeile in teile[1].splitlines():
            if not zeile.strip() or zeile.lstrip().startswith("#"):
                continue
            if ":" not in zeile:
                raise ValueError(f"{pfad}: Kopfzeile ohne Doppelpunkt: {zeile!r}")
            schluessel, wert = zeile.split(":", 1)
            kopf[schluessel.strip()] = wert.strip()
        for pflicht in ("name", "event", "pattern"):
            if not kopf.get(pflicht):
                raise ValueError(f"{pfad}: {pflicht} fehlt")
        if kopf["event"] not in ("bash", "prompt"):
            raise ValueError(f"{pfad}: event {kopf['event']!r} gibt es nicht")
        self.pfad = pfad
        self.name = kopf["name"]
        self.event = kopf["event"]
        self.action = kopf.get("action", "warn")
        if self.action not in ("warn", "block"):
            raise ValueError(f"{pfad}: action {self.action!r} gibt es nicht")
        if self.event == "prompt" and self.action == "block":
            raise ValueError(f"{pfad}: eine Prompt-Regel kann nicht blocken")
        self.an = kopf.get("enabled", "true").lower() != "false"
        self.muster = re.compile(kopf["pattern"], re.IGNORECASE)
        self.meldung = teile[2].strip()
        if not self.meldung:
            raise ValueError(f"{pfad}: Meldung fehlt")

    def trifft(self, text):
        return self.muster.search(text) is not None


def lade(verzeichnis, streng=False):
    regeln = []
    for pfad in sorted(glob.glob(os.path.join(verzeichnis, "*.md"))):
        try:
            regeln.append(Regel(pfad))
        except (ValueError, OSError, re.error) as fehler:
            if streng:
                raise
            # Eine kaputte Regel darf die anderen nicht mitnehmen - aber
            # schweigen darf sie auch nicht.
            print(f"claude-regeln: {pfad} uebersprungen: {fehler}", file=sys.stderr)
    return regeln


def projektverzeichnis(cwd):
    ort = os.path.abspath(cwd or os.getcwd())
    while True:
        kandidat = os.path.join(ort, ".claude", "riegel")
        if os.path.isdir(kandidat):
            return kandidat
        oben = os.path.dirname(ort)
        if oben == ort:
            return None
        ort = oben


def alle_regeln(cwd):
    regeln = []
    globale = os.environ.get("CLAUDE_REGELN_GLOBAL")
    if globale:
        regeln += lade(globale)
    projekt = projektverzeichnis(cwd)
    if projekt:
        # Gleicher Name: die Fassung des Projekts gewinnt.
        eigene = lade(projekt)
        namen = {r.name for r in eigene}
        regeln = [r for r in regeln if r.name not in namen] + eigene
    return [r for r in regeln if r.an]


def schon_gezeigt(sitzung, name):
    """Merkt sich die Warnung und sagt, ob sie in der Ruhespanne schon kam."""
    basis = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    ordner = os.path.join(basis, "claude-regeln")
    datei = os.path.join(ordner, re.sub(r"[^A-Za-z0-9_-]", "_", sitzung or "ohne") + ".json")
    jetzt = time.time()
    try:
        os.makedirs(ordner, mode=0o700, exist_ok=True)
        try:
            stand = json.load(open(datei))
        except (OSError, ValueError):
            stand = {}
        if jetzt - stand.get(name, 0) < RUHE_SEKUNDEN:
            return True
        stand[name] = jetzt
        with open(datei, "w") as aus:
            json.dump(stand, aus)
    except OSError:
        pass  # ohne Merkzettel lieber einmal zu oft warnen
    return False


def text_von(regeln):
    return "\n\n".join(f"[Regel {r.name}]\n{r.meldung}" for r in regeln)


def hook():
    eingabe = json.load(sys.stdin)
    ereignis = eingabe.get("hook_event_name", "")
    if ereignis == "PreToolUse" and eingabe.get("tool_name") == "Bash":
        art, text = "bash", (eingabe.get("tool_input") or {}).get("command") or ""
    elif ereignis == "UserPromptSubmit":
        art, text = "prompt", eingabe.get("prompt") or ""
    else:
        return
    if not text:
        return
    treffer = [r for r in alle_regeln(eingabe.get("cwd")) if r.event == art and r.trifft(text)]
    sperren = [r for r in treffer if r.action == "block"]
    if sperren:
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": text_von(sperren),
                }
            },
            sys.stdout,
        )
        return
    sitzung = eingabe.get("session_id", "")
    neu = [r for r in treffer if not schon_gezeigt(sitzung, r.name)]
    if neu:
        json.dump(
            {"hookSpecificOutput": {"hookEventName": ereignis, "additionalContext": text_von(neu)}},
            sys.stdout,
        )


def pruefen(verzeichnis, faelle_datei):
    """Jede Regel braucht Faelle, die treffen, und Faelle, die es nicht tun."""
    regeln = {r.name: r for r in lade(verzeichnis, streng=True)}
    faelle = json.load(open(faelle_datei, encoding="utf-8"))
    rot = 0
    for name in sorted(set(regeln) | set(faelle)):
        if name not in regeln:
            print(f"ROT  {name}: Faelle ohne Regel")
            rot += 1
            continue
        fall = faelle.get(name) or {}
        ja, nein = fall.get("trifft") or [], fall.get("trifft_nicht") or []
        if not ja or not nein:
            print(f"ROT  {name}: braucht mindestens einen Fall je Richtung")
            rot += 1
            continue
        falsch = [("sollte treffen", t) for t in ja if not regeln[name].trifft(t)]
        falsch += [("sollte NICHT treffen", t) for t in nein if regeln[name].trifft(t)]
        rot += len(falsch)
        print(f"{'ROT ' if falsch else 'ok  '} {name}  {regeln[name].action}  {len(ja)}+{len(nein)} Faelle")
        for art, t in falsch:
            print(f"       {art}: {t}")
    print(f"{len(regeln)} Regeln, rot: {rot}")
    return 1 if rot else 0


def main():
    argv = sys.argv[1:]
    if argv[:1] == ["pruefen"] and len(argv) == 3:
        sys.exit(pruefen(argv[1], argv[2]))
    if argv == ["hook"]:
        try:
            hook()
        except Exception as fehler:  # ein kaputter Hook darf keine Sitzung anhalten
            print(f"claude-regeln: {fehler}", file=sys.stderr)
        sys.exit(0)
    print(__doc__, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
