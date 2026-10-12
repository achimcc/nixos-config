---
name: warn-sleep-warteschleife
event: bash
pattern: \b(while|until)\b[^\n]*\bsleep\b|\bsleep\s+\d{2,}
---

**Warten heißt nicht pollen.** (im homeserver-Repo: Skill `warten`)

Gemessen: 2076 solcher Aufrufe in 172 Sitzungen, und 242 von Achims 2607
Prompts lauten „immer noch?". Stilles Warten in einer Schleife ist die Ursache.

Stattdessen:
- Den Lauf mit `run_in_background` starten, den echten Exit-Code ins Log.
- EIN Monitor auf das Prozessende, kein `sleep` in Schleife.
- Vorher eine Prognose nennen (Laufzeiten aus den lotse-Logs).
- Auf fremde Läufe: `lotse wait deploy --target server`, nie `pgrep -f`.
- Ungefragt melden, sobald sich etwas ändert, und in der Wartezeit an dem
  weiterarbeiten, was nicht davon abhängt.
