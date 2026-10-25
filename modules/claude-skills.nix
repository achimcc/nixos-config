# Eigene Kopien fremder Skills — gepinnt durch dieses Repo statt durch einen
# Marktplatz (Audit 4, B235/E-7, 2026-10-15).
#
# secskills: Aus dem Plugin secskills-core (github.com/trilwu/secskills,
# Einzelpfleger, unsigniert) wurden in 30 Tagen genau ACHT Skills gebraucht,
# alle in Audit 4. Zehn der dreissig wiesen an, URLs ueber den Fremddienst
# defuddle.md zu holen (`curl -sL "https://defuddle.md/<url>"`) — ein Dritter
# saehe jede gelesene URL und lieferte den Inhalt. Die acht liegen deshalb als
# eigene Kopie unter modules/claude-skills/secskills/, der Abschnitt
# „Reading External Sources" ist ersetzt (oeffentliche Quellen nur ueber
# WebFetch/firecrawl, nie eine URL des Hauses oder des Gegenstands). Herkunft
# und Commit: modules/claude-skills/secskills/HERKUNFT, Lizenz MIT (LICENSE).
# Das Marktplatz-Plugin und sein Marktplatz raeumt modules/claude-plugins.nix ab.
#
# Wer eine neue Fassung uebernimmt, liest den Diff und nimmt die defuddle-Zeile
# wieder heraus: `rg defuddle modules/claude-skills` muss leer bleiben.
#
# Als Nutzer-Skills unter ~/.claude/skills/<name> (ohne Namensraum,
# z. B. `vetting-agent-extensions`). Links in den Store: Die Skills schreiben
# nichts in ihr Verzeichnis.
{ lib, id, ... }:

let
  secskills = [
    "auditing-mcp-servers"
    "auditing-supply-chain"
    "maintaining-engagement-state"
    "orchestrating-vulnerability-research"
    "reporting-security-findings"
    "reviewing-cryptography"
    "securing-ai-systems"
    "vetting-agent-extensions"
  ];

  # Eigene Skills dieses Repos, unter modules/claude-skills/eigene/<name>.
  # speicherplatz-freigeben: aus der Plattenanalyse vom 2026-10-25 (94 % belegt).
  eigene = [
    "speicherplatz-freigeben"
  ];

  verweise = dir: names: map
    (name: {
      name = ".claude/skills/${name}";
      value.source = dir + "/${name}";
    })
    names;
in
{
  home-manager.users.${id.username} = {
    home.file = lib.listToAttrs (
      verweise ./claude-skills/secskills secskills
      ++ verweise ./claude-skills/eigene eigene
    );
  };
}
