# hs-riegel: Liegt JEDE Aenderung eines Commits (gegen seinen ersten Elter) in
# der Erlaubnisliste fuer GitHub-signierte Renovate-Commits?
#
# Aufruf: python3 inhalt.py <repo> <elter> <commit>
# Ausgabe: je Befund eine Zeile "<pfad>: <grund>"; je geaendertem GitHub-Knoten
# im flake.lock eine Zeile "HERKUNFT\t<owner>\t<repo>\t<ref|->\t<rev>" — die
# prueft der Aufrufer (liegt der neue Rev auf dem Zweig des Originals, oder nur
# irgendwo im Fork-Netz?).
# Exit 0: alles erlaubt. 1: mindestens ein Befund. 2: Werkzeugfehler.
#
# DIE ERLAUBNISLISTE IST ABSICHTLICH ENG. Was sie nicht kennt, ist nicht ok —
# dann wird der PR lokal geprueft und als eigener, signierter Commit
# uebernommen (git merge --squash). Jede Regel verlangt, dass nur der WERT
# sich aendert und der NAME bleibt: Ein gestohlenes Token darf keinen Eingang
# auf ein fremdes Repo, kein Image auf eine fremde Registry und keine Action
# auf einen fremden Autor umbiegen.

import difflib
import json
import re
import subprocess
import sys
import tomllib

repo, alt, neu = sys.argv[1:4]
befunde = []
herkunft = []


def git(*args):
    return subprocess.run(
        ["git", "-C", repo, "-c", "core.quotepath=off", *args],
        check=True,
        capture_output=True,
    ).stdout


def zeige(rev, pfad):
    return git("show", f"{rev}:{pfad}").decode("utf-8")


def befund(pfad, grund):
    befunde.append(f"{pfad}: {grund}")


# --- Zeilenweise Regeln -------------------------------------------------------
def zeilenpaare(pfad, a, b):
    """Nur ERSETZTE Zeilen, paarweise. Eingefuegte oder geloeschte Zeilen sind
    keine Versionsaenderung."""
    al, bl = a.splitlines(), b.splitlines()
    paare = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, al, bl, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        if op != "replace" or (i2 - i1) != (j2 - j1):
            befund(pfad, "Zeilen hinzugefuegt oder entfernt, nicht nur ersetzt")
            return None
        paare.extend(zip(al[i1:i2], bl[j1:j2]))
    return paare


USES = re.compile(r"^(\s*-?\s*uses:\s*)([^@\s#]+)@([^\s#]+)(\s*#.*)?$")


def workflow(pfad, a, b):
    for x, y in zeilenpaare(pfad, a, b) or []:
        mx, my = USES.match(x), USES.match(y)
        if not (mx and my):
            befund(pfad, "geaenderte Zeile ist keine uses:-Zeile")
        elif mx.group(1) != my.group(1) or mx.group(2) != my.group(2):
            befund(pfad, f"uses: wechselt die Action ({mx.group(2)} -> {my.group(2)})")


# Dasselbe Muster wie der customManager in renovate.json des homeserver-Repos.
OCI = re.compile(
    r'"(?P<name>(?:docker\.io|ghcr\.io)/[^"\s:@]+):(?P<tag>[^"\s@]+)@(?P<digest>sha256:[0-9a-f]{64})"'
)


def oci(pfad, a, b):
    for x, y in zeilenpaare(pfad, a, b) or []:
        mx, my = list(OCI.finditer(x)), list(OCI.finditer(y))
        if len(mx) != 1 or len(my) != 1:
            befund(pfad, "geaenderte Zeile ist keine Image-Zeile (Registry:Tag@sha256)")
            continue
        if mx[0].group("name") != my[0].group("name"):
            befund(pfad, f"Image wechselt den Namen ({mx[0].group('name')} -> {my[0].group('name')})")
            continue
        if OCI.sub("IMAGE", x) != OCI.sub("IMAGE", y):
            befund(pfad, "ausser dem Image aendert sich etwas in der Zeile")


# --- flake.lock -------------------------------------------------------------
VERAENDERLICH = ("rev", "narHash", "lastModified")


def flake_lock(pfad, a, b):
    try:
        la, lb = json.loads(a), json.loads(b)
    except ValueError:
        befund(pfad, "kein gueltiges JSON")
        return
    if {k: v for k, v in la.items() if k != "nodes"} != {k: v for k, v in lb.items() if k != "nodes"}:
        befund(pfad, "root oder version geaendert")
    na, nb = la.get("nodes", {}), lb.get("nodes", {})
    if set(na) != set(nb):
        befund(pfad, "Knoten hinzugefuegt oder entfernt: " + ", ".join(sorted(set(na) ^ set(nb))))
        return
    for name in sorted(na):
        ka, kb = json.loads(json.dumps(na[name])), json.loads(json.dumps(nb[name]))
        if ka == kb:
            continue
        loa, lob = ka.get("locked"), kb.get("locked")
        if not isinstance(loa, dict) or not isinstance(lob, dict):
            befund(pfad, f"Knoten {name}: mehr als locked geaendert")
            continue
        for k in VERAENDERLICH:
            loa.pop(k, None)
            lob.pop(k, None)
        if ka != kb:
            befund(pfad, f"Knoten {name}: mehr als rev/narHash/lastModified geaendert")
            continue
        rev_a, rev_b = na[name]["locked"].get("rev"), nb[name]["locked"].get("rev")
        if rev_a == rev_b:
            continue
        if lob.get("type") != "github" or not re.fullmatch(r"[0-9a-f]{40}", str(rev_b or "")):
            befund(pfad, f"Knoten {name}: Rev-Wechsel nur fuer type=github mit voller Rev")
            continue
        ref = (nb[name].get("original") or {}).get("ref") or "-"
        herkunft.append(f"HERKUNFT\t{lob['owner']}\t{lob['repo']}\t{ref}\t{rev_b}")


# --- Cargo ------------------------------------------------------------------
CRATES_IO = {
    "registry+https://github.com/rust-lang/crates.io-index",
    "sparse+https://index.crates.io/",
}


def cargo_lock(pfad, a, b):
    try:
        la, lb = tomllib.loads(a), tomllib.loads(b)
    except tomllib.TOMLDecodeError:
        befund(pfad, "kein gueltiges TOML")
        return
    if set(lb) - {"version", "package"} or la.get("version") != lb.get("version"):
        befund(pfad, "Kopf des Lockfiles geaendert")
    for p in lb.get("package", []):
        quelle = p.get("source")
        if quelle is not None and quelle not in CRATES_IO:
            befund(pfad, f"Paket {p.get('name')} aus fremder Quelle")


ABHAENGIGKEITEN = {"dependencies", "dev-dependencies", "build-dependencies"}


def cargo_norm(obj, oben=None):
    """Ersetzt jede Versionsangabe durch einen Platzhalter; alles andere bleibt."""
    if not isinstance(obj, dict):
        return obj
    aus = {}
    for k, v in obj.items():
        if k in ABHAENGIGKEITEN and isinstance(v, dict):
            dep = {}
            for n, d in v.items():
                if isinstance(d, str):
                    dep[n] = "VERSION"
                elif isinstance(d, dict) and "version" in d:
                    dep[n] = {**d, "version": "VERSION"}
                else:
                    dep[n] = d
            aus[k] = dep
        elif k == "version" and oben == "package" and isinstance(v, str):
            aus[k] = "VERSION"
        else:
            aus[k] = cargo_norm(v, k)
    return aus


def cargo_toml(pfad, a, b):
    try:
        ta, tb = tomllib.loads(a), tomllib.loads(b)
    except tomllib.TOMLDecodeError:
        befund(pfad, "kein gueltiges TOML")
        return
    if cargo_norm(ta) != cargo_norm(tb):
        befund(pfad, "mehr als Versionsangaben geaendert")


def regel(pfad):
    teile = pfad.split("/")
    if pfad == "flake.lock":
        return flake_lock
    if len(teile) == 3 and teile[:2] == [".github", "workflows"] and re.search(r"\.ya?ml$", pfad):
        return workflow
    if teile[0] == "hosts" and len(teile) > 1 and pfad.endswith(".nix"):
        return oci
    if teile[-1] == "Cargo.lock":
        return cargo_lock
    if teile[-1] == "Cargo.toml":
        return cargo_toml
    return None


def main():
    teile = git("diff", "--raw", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", alt, neu).split(b"\0")
    i = 0
    while i + 1 < len(teile) and teile[i]:
        meta, pfad = teile[i].decode(), teile[i + 1].decode("utf-8", "replace")
        i += 2
        modus_a, modus_b, _, _, status = meta.lstrip(":").split()
        if status != "M" or modus_a != "100644" or modus_b != "100644":
            befund(pfad, f"nur geaenderte normale Dateien erlaubt (Status {status}, Modus {modus_a}->{modus_b})")
            continue
        r = regel(pfad)
        if r is None:
            befund(pfad, "nicht auf der Erlaubnisliste")
            continue
        try:
            r(pfad, zeige(alt, pfad), zeige(neu, pfad))
        except UnicodeDecodeError:
            befund(pfad, "kein UTF-8")


try:
    main()
except (subprocess.CalledProcessError, ValueError) as e:
    print(f"inhalt: Werkzeugfehler: {e}", file=sys.stderr)
    sys.exit(2)

for z in befunde + herkunft:
    print(z)
sys.exit(1 if befunde else 0)
