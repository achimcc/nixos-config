# nixd als Language Server fuer Claude Code — das LSP-Werkzeug (Definition,
# Referenzen, Hover, Symbole) und die Diagnose nach jedem Edit auch fuer
# .nix-Dateien. 2026-10-25.
#
# WARUM EIN EIGENES PLUGIN: Anthropics Marktplatz hat LSP-Plugins fuer zwoelf
# Sprachen, Nix ist nicht dabei. Die Plugins von Dritten
# (boostvolt/claude-code-lsps, SolAstrius/nix-lsp) waeren ein neuer Marktplatz
# — genau das, was modules/claude-plugins.nix abgebaut hat (E-2). Ein
# LSP-Plugin ist aber nur eine plugin.json mit `lspServers`; die steht hier,
# und der Befehl zeigt in den Store statt auf ein nixd im PATH.
#
# Eingebunden wie modules/claude-werkbank.nix ueber CLAUDE_CODE_PLUGIN_DIRS,
# mit FESTEM Ordner (~/.local/share/claude-mods/nixd-lsp). Die plugin.json
# darin ist ein home-manager-Link in den Store — ein Store-Pfad direkt in der
# Liste haette sich bei jedem Rebuild geaendert, und der alte Eintrag waere
# als zweites Plugin gleichen Namens stehen geblieben.
#
# KONFIGURATION (Feld `settings`, Abschnitt `nixd`): Claude Code beantwortet
# damit nixds workspace/configuration-Anfrage (gelesen im Quelltext von
# 2.1.310). Gesetzt ist nur nixpkgs — das nixpkgs DIESES Systems, lazy
# ausgewertet, fuer Paket- und lib-Vervollstaendigung.
#
# BEWUSST NICHT GESETZT: `options` (NixOS-/home-manager-Optionen). Dafuer
# muesste nixd eine ganze Systemkonfiguration auswerten — fuer den Homeserver
# 12–17 GB, und das in JEDER Sitzung, die eine .nix-Datei anfasst, an lotse
# vorbei. Bei einem Dutzend paralleler Sitzungen sprengt das die 30 GB.
{ pkgs, id, ... }:

let
  plugin = {
    name = "nixd-lsp";
    version = pkgs.nixd.version;
    description = "Nix-Sprachunterstuetzung ueber nixd (nixpkgs, deklariert in ~/nixos-config)";
    lspServers.nixd = {
      command = "${pkgs.nixd}/bin/nixd";
      extensionToLanguage.".nix" = "nix";
      settings.nixd.nixpkgs.expr = "import ${pkgs.path} { }";
      maxRestarts = 3;
    };
  };
in
{
  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.file.".local/share/claude-mods/nixd-lsp/.claude-plugin/plugin.json".text =
        builtins.toJSON plugin;

      home.activation.claudeNixdLsp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        ordner="$HOME/.local/share/claude-mods/nixd-lsp"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --arg ordner "$ordner" '
              .env.CLAUDE_CODE_PLUGIN_DIRS = (
                ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(length > 0)))
                + [ $ordner ] | unique | join(":")
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-nixd-lsp: $datei ist kein gueltiges JSON — der Eintrag wurde NICHT gesetzt." >&2
        fi
      '';
    };
}
