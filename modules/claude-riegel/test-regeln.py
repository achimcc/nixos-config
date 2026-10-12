"""Prueft, welche Regeln ein Projekt beisteuern darf (laeuft im Bau des Regelsatzes).

  python3 test-regeln.py

Faelle fuer die Muster selbst stehen in faelle.json; hier geht es um die Frage,
wessen Regeln ueberhaupt geladen werden.
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regeln  # noqa: E402


def schreibe(ordner, name, action, meldung, extra=""):
    os.makedirs(ordner, exist_ok=True)
    with open(os.path.join(ordner, name + ".md"), "w", encoding="utf-8") as aus:
        aus.write(f"---\nname: {name}\nevent: bash\npattern: x\naction: {action}\n{extra}---\n{meldung}\n")


def lauf(vertraut):
    """Globale Regeln sperre (block) und hinweis (warn); das Projekt ueberschreibt beide."""
    with tempfile.TemporaryDirectory() as wurzel:
        wurzel = os.path.realpath(wurzel)
        globale = os.path.join(wurzel, "global")
        projekt = os.path.join(wurzel, "repo")
        schreibe(globale, "sperre", "block", "global")
        schreibe(globale, "hinweis", "warn", "global")
        riegel = os.path.join(projekt, ".claude", "riegel")
        schreibe(riegel, "sperre", "warn", "projekt", "enabled: false\n")
        schreibe(riegel, "hinweis", "warn", "projekt")
        schreibe(riegel, "eigene", "block", "projekt")
        os.environ["CLAUDE_REGELN_GLOBAL"] = globale
        os.environ["CLAUDE_REGELN_VERTRAUT"] = projekt if vertraut else os.path.join(wurzel, "anderswo")
        unterordner = os.path.join(projekt, "tief", "unten")
        os.makedirs(unterordner)
        return {r.name: (r.action, r.meldung) for r in regeln.alle_regeln(unterordner)}


def main():
    rot = 0

    def erwarte(was, ist, soll):
        nonlocal rot
        if ist != soll:
            rot += 1
            print(f"ROT  {was}: {ist!r}, erwartet {soll!r}")
        else:
            print(f"ok   {was}")

    fremd = lauf(vertraut=False)
    erwarte("fremdes Repo: nur die globalen Regeln", fremd,
            {"sperre": ("block", "global"), "hinweis": ("warn", "global")})

    eigen = lauf(vertraut=True)
    erwarte("vertrautes Repo: globale Sperre bleibt", eigen.get("sperre"), ("block", "global"))
    erwarte("vertrautes Repo: Warnung ueberschreibbar", eigen.get("hinweis"), ("warn", "projekt"))
    erwarte("vertrautes Repo: eigene Regel kommt dazu", eigen.get("eigene"), ("block", "projekt"))

    os.environ.pop("CLAUDE_REGELN_VERTRAUT", None)
    with tempfile.TemporaryDirectory() as wurzel:
        schreibe(os.path.join(wurzel, ".claude", "riegel"), "eigene", "block", "projekt")
        os.environ["CLAUDE_REGELN_GLOBAL"] = os.path.join(wurzel, "leer")
        erwarte("ohne Liste: kein Projekt ist vertraut", regeln.alle_regeln(wurzel), [])

    print(f"rot: {rot}")
    return 1 if rot else 0


if __name__ == "__main__":
    sys.exit(main())
