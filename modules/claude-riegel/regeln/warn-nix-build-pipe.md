---
name: warn-nix-build-pipe
event: bash
pattern: ^(?![\s\S]*(PIPESTATUS|pipefail))[\s\S]*\bnix\s+(build|flake\s+check)\b((?!&&)[^;\n|])*\|\s*(tail|head|grep)\b
---

**`nix build … | tail` liefert tails Exit-Code.**

Ein roter Bau sieht so grün aus. Gemessen: 220 Aufrufe in 65 Sitzungen.

Stattdessen eines von beiden:
- `nix build … 2>&1 | tail -40; echo "exit=${PIPESTATUS[0]}"`
- Ausgabe in eine Datei, Exit-Code direkt prüfen, danach die Datei lesen.

Läuft der Aufruf über `lotse run --class=eval --`, steht der echte Code in der
letzten Zeile (`lotse: exit=…`); 200 und 201 sind kein Prüfergebnis.
