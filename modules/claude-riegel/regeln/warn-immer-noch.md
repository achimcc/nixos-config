---
name: warn-immer-noch
event: prompt
pattern: ^\s*((l(ä|ae)uf(t|st)|warte(s)?t|steht|h(ä|ae)ngt|deployst)\b.{0,60})?immer\s+noch(\s+nicht)?\s*\?*\s*$|^\s*(wartest|l(ä|ae)ufst)\s+du\b.{0,40}\?\s*$
---

**Achim musste nachfragen. Das ist der Fehler, nicht die Frage.**

242 seiner 2607 Prompts lauten so. Die Antwort ist eine MESSUNG, kein „ja,
läuft noch":

1. Stand messen: `lotse status`, die letzten Zeilen des Logs, Laufzeit bisher.
2. Prognose nennen, aus den lotse-Logs früherer Läufe, mit Uhrzeit.
3. Läuft es länger als die Prognose: Ursache suchen (Warteschlange, Speicher,
   Netz, fremder Lauf), nicht weiter warten.
4. Einen Monitor auf das Prozessende setzen und ungefragt melden.
5. In der Wartezeit an dem weiterarbeiten, was nicht davon abhängt.

Im homeserver-Repo: Skill `warten`.
