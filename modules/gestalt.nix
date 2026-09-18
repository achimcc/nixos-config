# gestalt — zeigt die FORM einer JSON-Antwort, nicht ihre Werte
# (github.com/achimcc/gestalt). Systemweit statt nur in der devShell des
# homeserver-Repos, damit die Regel in ~/.claude/CLAUDE.md („JSON im Chat nur
# durch gestalt") in JEDEM Projekt gilt und nicht an einem geladenen direnv hängt.
{ pkgs, inputs, ... }:

{
  environment.systemPackages = [
    inputs.gestalt.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
