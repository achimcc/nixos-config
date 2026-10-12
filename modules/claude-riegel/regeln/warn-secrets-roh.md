---
name: warn-secrets-roh
event: bash
pattern: \b(cat|less|head|tail|bat)\s+[^|;&\n]*(/run/secrets|/run/credentials|\.env\b|secrets/\S+\.ya?ml)(?![^\n]*\|\s*(sed\s+-E?\s*\S*s/|sha256sum|wc\b|gestalt))|\bsops\s+(-d|--decrypt|decrypt)\b(?![^\n]*(>|\|\s*(sha256sum|wc\b|gestalt|sed\s)))
---

**Hier kann ein Geheimnis im Klartext im Chat landen.**

Die Maske ist der Vorgabewert, nicht die Reaktion auf einen Verdacht. So sind
schon zweimal echte Schlüssel im Chat gelandet (beide rotiert).

- YAML, INI, `.env`, Unit-Dateien: JEDE Wertzeile maskieren,
  `sed -E 's/(: |=).*/\1<verdeckt>/'`. Nie eine Auswahl von Feldnamen.
- JSON: `… | gestalt`, dann `gestalt -s '<pfad>'`.
- „Ist es derselbe Wert?": Hashes beider Seiten (`sha256sum`,
  `gestalt --hash <pfad>`), nie der Klartext.
- Struktur einer sops-Datei prüfen: Schlüsselnamen und Längen, nicht Werte.
