---
name: warn-pgrep-f-pkill
event: bash
pattern: \bpgrep\s+-[a-z]*f|\b(pkill|killall)\b
---

**`pgrep -f` trifft die eigene Kommandozeile, `pkill` trifft fremde Sitzungen.**

Das Muster steht in der Kommandozeile des Aufrufs selbst; eine Warteschleife
darauf endet nie oder sofort. Ein maschinenweites `pkill` beendet die Läufe der
anderen Sitzungen. Gemessen: 1385 bzw. 57 Aufrufe.

Stattdessen:
- Wer baut, wertet aus, deployt: `lotse status`.
- Auf ein fremdes Ende warten: `lotse wait deploy --target server`.
- Einen eigenen Prozess beenden: über seine PID (`kill <pid>`), die beim Start
  notiert wurde.
