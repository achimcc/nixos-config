# Der Eintrag des Paperless-MCP fuer eine projektweite `.mcp.json`. EINE
# Definition fuer zwei Projekte: ~/Dokumente/Papiere (mcp-paperless.nix) und
# ~/Dokumente/Steuer (mcp-elster.nix, dort zusammen mit dem Elster-Server),
# damit beide Dateien bei einer Aenderung des Wrappers nicht auseinanderlaufen.
# Pfad ueber /run/current-system statt Store-Pfad: Begruendung in mcp-nixos.nix.
{
  type = "stdio";
  command = "/run/current-system/sw/bin/mcp-ohne-schluessel";
  args = [ "/run/current-system/sw/bin/paperless-mcp-homeserver" ];
  env = { };
}
