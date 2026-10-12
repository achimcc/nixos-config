---
name: block-nixos-config-bauen
event: bash
pattern: (?m)(^|[;&|(]\s*)(sudo\s+)?(nixos-rebuild\s+(switch|boot|test|build|dry-activate|dry-build)|nrs)\b|nixos-config[^\n]*\bnix\s+build\b|\bnix\s+build\b[^\n]*nixos-config
action: block
---

**`~/nixos-config` baut nur Achim.**

`nrs` und `nixos-rebuild` brauchen root, im Tool-Bash gibt es kein Askpass:
Der Aufruf hängt oder scheitert (Achim am 2026-10-09: „du kannst ein nrs doch
sowieso nicht ausführen, das benötigt root"). Gemessen in 86 Aufrufen in 39
Sitzungen.

Stattdessen: Datei editieren, Syntax prüft der Hook `nix-parse` von selbst,
dann Achim sagen, dass ein `nrs` aussteht, und was es bewirkt. Nicht darauf
warten; mit dem weiterarbeiten, was davon nicht abhängt.
