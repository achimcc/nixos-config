---
name: warn-schluessel-in-argv
event: bash
pattern: -H\s+\S?(X-Api-Key|Authorization|X-Emby-Token|X-MediaBrowser-Token|X-Auth-Token|Cookie)\b|[?&](apikey|api_key|access_token|token)=
---

**Ein Schlüssel in argv oder in der URL landet im Journal und in `ps`.**

Ein `systemd-run`-Einzeiler mit `-H 'X-Api-Key: …'` schreibt den Schlüssel ins
Gastjournal (`caveats/systemd-run-einzeiler-schluessel-im-journal.md`); eine
URL mit `?apikey=` steht zusätzlich in Caddys Zugriffslog.

Stattdessen:
- Im Gast: `vantage run --header-file <datei> …` (Skill `vantage`).
- Sonst: Schlüssel in eine Datei, dann `curl -K <curlrc>`.
- Nie den Wert per `$(…)` in die Kommandozeile einsetzen.
