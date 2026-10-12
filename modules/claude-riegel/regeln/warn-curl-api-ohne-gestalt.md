---
name: warn-curl-api-ohne-gestalt
event: bash
pattern: ^(?![\s\S]*(gestalt|jq\s+-[a-z]*r|\s-o\s|--output|http_code|sha256sum|\|\s*wc\b|>\s*\S))[\s\S]*\bcurl\b[^\n]*/(api|v\d)/
---

**API-Antwort ohne `gestalt`: JSON landet roh im Chat.**

API-Antworten tragen Schlüssel, auch die, von denen man glaubt, sie enthielten
nur Einstellungen (`caveats/api-antworten-tragen-schluessel.md`). Der Riegel
`json-roh` fängt nur `jq .` am Ende; ein nacktes `curl` fängt er nicht.

Stattdessen:
- Erst die Form: `ssh root@server "curl -s …" | gestalt`
- Dann genau die Felder: `… | gestalt -s '<pfad>'`, Pfad aus der vorigen
  Ausgabe kopiert.
- `jq -r '.feld'` nur, wo der Wert weiterverarbeitet wird und nicht im Chat
  erscheint.

`gestalt` läuft auf der Workstation, nicht im Gast und nicht auf dem Wirt.
