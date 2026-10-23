# playwright-mcp — Browser-Automatisierung fuer Claude Code
# (github.com/Microsoft/playwright-mcp), 2026-10-11 auf Achims Wunsch, global.
#
# Paket aus nixpkgs. Dessen Wrapper erledigt schon zwei Dinge:
#   - PLAYWRIGHT_BROWSERS_PATH zeigt auf playwright-driver.browsers. Es wird also
#     kein Browser zur Laufzeit heruntergeladen. npx-Varianten tun das, und unter
#     NixOS laufen die geladenen Binaries ohnehin nicht.
#   - PLAYWRIGHT_MCP_ISOLATED=1, solange kein Profilordner gesetzt ist: Jede
#     Sitzung startet mit einem frischen, fluechtigen Profil. Keine Cookies und
#     keine Anmeldung bleiben zwischen den Sitzungen liegen.
#
# `--headless`: Claude Code laeuft im Terminal, oft in einem Dutzend Sitzungen
# nebeneinander. Ein sichtbares Fenster je Sitzung stoert nur. Wer zusehen
# will, startet eine Sitzung mit `claude mcp add` ohne das Flag (Projekt-Scope).
#
# `--output-dir`: Screenshots und PDFs landen sonst in einem Ordner unter /tmp.
# Hier liegen sie unter ~/.local/share/playwright-mcp und sind wiederzufinden.
#
# Eingetragen wird wie bei mcp-nixos.nix in ~/.claude.json (user scope). Die
# Begruendung fuer das Aktivierungsskript statt eines Symlinks steht dort.
#
# Neben diesem Server bleibt das Plugin chrome-devtools-mcp aktiv. Beide
# ueberschneiden sich; entfernt wird erst, was sich im Gebrauch nicht bewaehrt.
{ pkgs, id, ... }:

let
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/mcp-ohne-schluessel";
    args = [
      "/run/current-system/sw/bin/playwright-mcp"
      "--headless"
      "--output-dir"
      "/home/${id.username}/.local/share/playwright-mcp"
    ];
    env = { };
  };
in
{
  environment.systemPackages = [ pkgs.playwright-mcp ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeMcpPlaywright = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p -m 700 "$HOME/.local/share/playwright-mcp"
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { playwright: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-playwright: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
