# claude-obsidian — Claude Code legt Gelesenes als verlinkte Markdown-Notizen
# im eigenen Obsidian-Vault ab (github.com/AgriciDaniel/claude-obsidian).
#
# ZWEI TEILE, und der zweite ist der, an dem es sonst scheitert:
#
#  1. Das Plugin, GEPINNT (Audit 4, B174/E-2, 2026-10-15). Bis dahin stand
#     hier ein Marktplatz-Eintrag (`agricidaniel-claude-obsidian`), und Claude
#     Code zog bei jeder `/plugin`-Auffrischung den HEAD eines Einzelpflegers —
#     samt SessionStart-Hook (Python), der mit dem ssh-Agenten laeuft. Jetzt
#     dieselbe Bauart wie modules/claude-savvy.nix: `fetchFromGitHub` mit Rev
#     und Hash, eine schreibbare Kopie unter ~/.local/share/claude-mods/,
#     eingebunden ueber `env.CLAUDE_CODE_PLUGIN_DIRS`. Der Rev ist der Commit,
#     der bis dahin installiert war und im Audit gelesen wurde (2.2.0; Baum
#     gleich dem Marktplatz-Klon). Wer den Rev hebt, liest vorher den Diff von
#     hooks/ und scripts/. Den alten Marktplatz-Eintrag samt Plugin raeumt
#     modules/claude-plugins.nix ab (Liste `entfernen`).
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
# deshalb nur `env.CLAUDE_CODE_PLUGIN_DIRS` — idempotent, alles andere bleibt
# unberuehrt.
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
# WIE WEIT „deklarativ" TRAEGT: seit B174 bis zur Fassung — Rev und Hash
# stehen hier, ein Auto-Update gibt es nicht mehr. Die Kopie wird NUR erneuert,
# wenn sich der Store-Pfad aendert (eine laufende Sitzung beobachtet den Ordner).
{ pkgs, id, ... }:

let
  vault = "/home/${id.username}/Dokumente/Obsidian";

  # B174: gepinnt statt Marktplatz. Rev = bis 2026-10-15 installierter Commit.
  quelle = pkgs.fetchFromGitHub {
    owner = "AgriciDaniel";
    repo = "claude-obsidian";
    rev = "32ac5a02c4e082e4a5628ca810776375e134708e";
    hash = "sha256-GwVTOKtbSUOKYgpx7LZSIRNqw8EL3/PsPK4ucOsyRu4=";
  };
in
{
  # Python braucht das Plugin ab 3.11 (`scripts/claude-obsidian.py`);
  # `configuration.nix` fuehrt python3 bereits in den systemPackages.
  environment.sessionVariables.CLAUDE_OBSIDIAN_VAULT = vault;

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      # Nach claudeOfficialPlugins, das den alten Marktplatz-Eintrag abraeumt.
      home.activation.claudeObsidianPlugin = lib.hm.dag.entryAfter [ "writeBoundary" "claudeOfficialPlugins" ] ''
        datei="$HOME/.claude/settings.json"
        basis="$HOME/.local/share/claude-mods"
        ziel="$basis/claude-obsidian"
        marke="$basis/claude-obsidian.quelle"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        if [ "$(${pkgs.coreutils}/bin/cat "$marke" 2>/dev/null || true)" != "${quelle}" ] \
          || [ ! -e "$ziel/.claude-plugin/plugin.json" ]; then
          run ${pkgs.coreutils}/bin/mkdir -p "$basis"
          run ${pkgs.coreutils}/bin/rm -rf "$ziel"
          run ${pkgs.coreutils}/bin/cp -r --no-preserve=mode,ownership "${quelle}" "$ziel"
          run sh -c 'printf "%s\n" "$1" > "$2"' _ "${quelle}" "$marke"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --arg ziel "$ziel" '
              .env.CLAUDE_CODE_PLUGIN_DIRS = (
                ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(length > 0)))
                + [ $ziel ] | unique | join(":")
              )
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
