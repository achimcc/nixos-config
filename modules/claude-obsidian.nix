# claude-obsidian — Claude Code legt Gelesenes als verlinkte Markdown-Notizen
# im eigenen Obsidian-Vault ab (github.com/AgriciDaniel/claude-obsidian).
#
# ZWEI TEILE, und der zweite ist der, an dem es sonst scheitert:
#
#  1. Der Marktplatz-Eintrag. Das Projekt ist ein Claude-Code-Plugin MIT
#     eigenem Marktplatz (`.claude-plugin/marketplace.json`, Name
#     `agricidaniel-claude-obsidian`, Plugin `claude-obsidian`). Der globale
#     Hebel dafuer sind `extraKnownMarketplaces` und `enabledPlugins` in
#     ~/.claude/settings.json — dieselbe Stelle, an der `thedotmack` schon
#     steht. Claude Code klont den Marktplatz daraufhin selbst nach
#     ~/.claude/plugins/marketplaces/.
#
#  2. DER VAULT, und ohne ihn tut das Plugin NICHTS. Es loest seinen Vault aus
#     `CLAUDE_OBSIDIAN_VAULT`, der naechsten `.claude-obsidian.json` oder einem
#     eindeutig initialisierten Vorfahren auf — und bricht bei Unklarheit
#     ausdruecklich ab, statt irgendwo zu schreiben. Eine Sitzung in
#     ~/nixos-config faende gar nichts. Die Variable ist also das, was „global"
#     hier ueberhaupt bedeutet.
#
# WARUM `environment.sessionVariables` UND NICHT `home.sessionVariables`:
# Letzteres wirkt ueber ~/.profile und erreicht aus GNOME gestartete
# Anwendungen nicht zuverlaessig — das steht als Lehre schon in home.nix:101
# (GSK_RENDERER musste aus demselben Grund nach desktop.nix). Claude Code
# startet hier aus wezterm, aber eben nicht nur.
#
# WARUM EIN AKTIVIERUNGSSKRIPT UND KEIN SYMLINK: ~/.claude/settings.json
# schreibt Claude Code selbst (Modellwahl, Plugin-Schalter). Als Link in den
# Store waere sie schreibgeschuetzt und `/model` schluege fehl. Das Skript setzt
# deshalb genau ZWEI Schluessel — idempotent, alles andere bleibt unberuehrt.
# Eine Datei, die kein gueltiges JSON ist, fasst es nicht an. Dieselbe Bauart
# wie der lotse-Hook in modules/lotse.nix und der Servereintrag in
# modules/mcp-nixos.nix.
#
# WAS HIER BEWUSST NICHT STEHT: die Uebernahme des Vaults (`adopt`). Sie ist im
# Programm zweistufig gebaut — erst ein Plan samt SHA-256, dann `--apply
# --approved-plan-sha256` —, damit ein Mensch dazwischen liest. In einem
# Aktivierungsskript liefe sie bei JEDEM Rebuild gegen einen Vault, der per Git
# auf obsi-01 synchronisiert wird. Einmalig von Hand, nicht hier.
#
# WIE WEIT „deklarativ" TRAEGT: Diese Datei legt fest, WELCHER Marktplatz,
# WELCHES Plugin und WELCHER Vault. Den Plugin-CODE holt Claude Code selbst von
# GitHub und aktualisiert ihn eigenstaendig — wie bei superpowers und
# claude-mem auch. Eine Auswertung dieses Repos stellt die Eintraege wieder
# her, nicht eine bestimmte Plugin-Fassung.
{ pkgs, id, ... }:

let
  vault = "/home/${id.username}/Dokumente/Obsidian";

  marktplatz = builtins.toJSON {
    source = {
      source = "github";
      repo = "AgriciDaniel/claude-obsidian";
    };
  };
in
{
  # Python braucht das Plugin ab 3.11 (`scripts/claude-obsidian.py`);
  # `configuration.nix` fuehrt python3 bereits in den systemPackages.
  environment.sessionVariables.CLAUDE_OBSIDIAN_VAULT = vault;

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeObsidianPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson markt ${lib.escapeShellArg marktplatz} '
              .extraKnownMarketplaces["agricidaniel-claude-obsidian"] = $markt
              | .enabledPlugins["claude-obsidian@agricidaniel-claude-obsidian"] = true
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "claude-obsidian: $datei ist kein gueltiges JSON — der Eintrag wurde NICHT gesetzt." >&2
        fi
      '';
    };
}
