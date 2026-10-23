# Die Huelle vor jedem MCP-Server: keine Sitzungsschluessel in seiner Umgebung
# (Audit 4, 2026-10-15, B171).
#
# Jeder stdio-Server erbt die Umgebung der Claude-Sitzung, und darin stehen
# GH_TOKEN (fine-grained, lesend), SOPS_AGE_KEY_FILE (TPM-Identitaet) und
# SSH_AUTH_SOCK (ssh-tpm-agent mit den Schluesseln bis root@server). Gemessen am
# laufenden filesystem-Server: alle drei im environ. Kein Server braucht sie —
# github holt sein Token selbst aus sops, git pusht nicht, die uebrigen lesen
# ihre Geheimnisse ueber eigene Wrapper. Was ein Server nicht hat, kann ein
# fehlgeleiteter Aufruf (Prompt-Injection ueber eine Tool-Ausgabe) nicht
# weitergeben.
#
# Eingehaengt als `command` in den Eintraegen der sechs home-manager-Module
# (mcp-filesystem, -git, -nixos, -firecrawl, -paperless, -playwright); elster
# und grafana (project scope, eigene .mcp.json) tragen das `unset` in ihrem
# Wrapper selbst.
{ pkgs, ... }:

let
  huelle = pkgs.writeShellApplication {
    name = "mcp-ohne-schluessel";
    text = ''
      exec env -u GH_TOKEN -u GITHUB_TOKEN -u SOPS_AGE_KEY_FILE -u SSH_AUTH_SOCK -- "$@"
    '';
  };
in
{
  environment.systemPackages = [ huelle ];
}
