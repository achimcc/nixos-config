# AGENTS.md

Die Anweisungen für Agenten in diesem Repo stehen in [`CLAUDE.md`](CLAUDE.md) — dort lesen, nicht
hier. Diese Datei bleibt nur als Einstieg für Werkzeuge, die `AGENTS.md` suchen.

Das Wichtigste vorweg: **Die Systemkonfiguration wird nicht von einer Sitzung gebaut** — kein
`nixos-rebuild`, kein Ersatzbau von `system.build.toplevel`. Den Rebuild (`nrs`) startet der Nutzer
selbst; er braucht root und den FIDO2-Stick.

Nutzerdokumentation: [`README.md`](README.md).
