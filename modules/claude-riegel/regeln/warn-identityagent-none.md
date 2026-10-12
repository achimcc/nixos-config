---
name: warn-identityagent-none
event: bash
pattern: IdentityAgent[= ]none
---

**`IdentityAgent=none` schließt die TPM-Schlüssel aus.**

`~/.ssh/id_ecdsa` und `id_ecdsa_colmena` liegen seit dem 2026-09-23 im TPM
(ssh-tpm-agent) und sind nur über den Agenten nutzbar. Mit
`IdentityAgent=none` scheitert die Anmeldung an Server und VPS.

- Server: `ssh colmena-deploy@<host> '…'` oder `ssh root@<host> '…'`, `-i`
  zeigt auf die `.pub`-Datei.
- VPS: `ssh -F ssh_config vps`.
- Ausnahme: Schlüssel, die als Datei vorliegen (Router `id_rsa_router`,
  gvfs-Fall). Dort ist die Option richtig.
