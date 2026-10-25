#!/usr/bin/env bash
# Bestandsaufnahme des Plattenplatzes — nur lesend, loescht nichts.
# Jede Messung hat eine Zeitgrenze: unter Last (parallele Bauten, eine andere
# Aufraeum-Sitzung) braucht ein du ueber 60 Projekte sonst Viertelstunden.
set -u

T=${T:-240}            # Sekunden je Messung
P=${PROJECTS:-$HOME/Projects}

abschnitt() { printf '\n========== %s ==========\n' "$1"; }

# Je Pfad ein eigenes du mit eigener Zeitgrenze: ein einziges du ueber alle
# brach am 2026-10-25 unter Last mittendrin ab und liess .local und .config
# stillschweigend aus. Wer die Grenze reisst, steht als "> Zeitgrenze" da.
groesse() {
  local p
  for p in "$@"; do
    [ -e "$p" ] || continue
    timeout "$T" du -xsh "$p" 2>/dev/null || printf '>%ss\t%s (Zeitgrenze)\n' "$T" "$p"
  done | sort -rh
}

abschnitt "Dateisystem"
df -h -x tmpfs -x devtmpfs -x efivarfs -x fuse.sshfs

abschnitt "Laeufe (lotse status)"
command -v lotse >/dev/null && lotse status 2>&1 | head -20 || echo "lotse fehlt im PATH"

abschnitt "Home, oberste Ebene"
groesse "$HOME"/* "$HOME"/.[!.]* | head -25

abschnitt "Caches"
groesse "$HOME"/.cache/* "$HOME"/.npm/_cacache "$HOME"/.cargo/registry \
  "$HOME"/.cargo/git "$HOME"/.rustup/toolchains/* | head -25

abschnitt "~/.local/share"
groesse "$HOME"/.local/share/* | head -20

abschnitt "Rust target/ in $P (groesste 30, Summe)"
liste=$(mktemp)
timeout "$T" fd -H -I -t d --prune '^target$' "$P" 2>/dev/null \
  | tr '\n' '\0' | timeout "$T" xargs -0 -r du -xs 2>/dev/null | sort -rn >"$liste"
awk '{s+=$1; n++} END {printf "%d Verzeichnisse, %.1f GiB\n", n, s/1048576}' "$liste"
head -30 "$liste" | awk '{printf "%7.1f GiB  %s\n", $1/1048576, $2}'
rm -f "$liste"

abschnitt "Andere Bau-Artefakte (node_modules, .venv, .direnv) in $P"
timeout "$T" fd -H -I -t d --prune '^(node_modules|\.venv|venv|\.direnv)$' "$P" 2>/dev/null \
  | tr '\n' '\0' | timeout "$T" xargs -0 -r du -xs 2>/dev/null \
  | awk '{n=$2; sub(/\/$/,"",n); sub(/.*\//,"",n); s[n]+=$1; c[n]++}
         END {for (k in s) printf "%-14s %4d Stueck %6.1f GiB\n", k, c[k], s[k]/1048576}'

abschnitt "Nix: Generationen"
echo "System: $(ls -1d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)," \
  "Home-Manager: $(ls -1d "$HOME"/.local/state/nix/profiles/home-manager-*-link 2>/dev/null | wc -l)"
ls -ld --time-style=+%F /nix/var/nix/profiles/system-*-link 2>/dev/null | awk '{print "  " $6, $7}'

abschnitt "Nix: GC-Wurzeln nach Herkunft"
timeout "$T" nix-store --gc --print-roots 2>/dev/null | grep -v '^/proc' | grep -v censored \
  | awk '{print $1}' | tr -d '"' \
  | sed -E "s#^$HOME/Projects/([^/]+-worktrees)/.*#Projects/\1/*#; s#^$HOME/Projects/([^/]+)/.*#Projects/\1#; s#^/tmp/claude-1000/.*#/tmp/claude-1000 (Scratchpads)#; s#^/tmp/.*#/tmp (sonstige)#; s#^/nix/var/nix/profiles/.*#Profile#; s#^$HOME/([^/]+).*#~/\1#" \
  | sort | uniq -c | sort -rn | head -20

abschnitt "Nix: tote Pfade (was nix-store --gc loeschen wuerde)"
echo "$(timeout "$T" nix-store --gc --print-dead 2>/dev/null | wc -l) Pfade (Zahl, keine Groesse: du ueber Hardlinks taeuscht)"

abschnitt "Worktrees im homeserver-Repo"
hs=$P/homeserver
if [ -d "$hs/.git" ]; then
  gemergt=$(git -C "$hs" branch --merged main --format='%(refname:short)' 2>/dev/null)
  git -C "$hs" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{sub("refs/heads/","",$2); print w, $2}' \
    | while read -r wt zweig; do
        [ "$wt" = "$hs" ] && continue
        m=nein; grep -qxF "$zweig" <<<"$gemergt" && m=ja
        schmutz=$(git -C "$wt" status --short 2>/dev/null | wc -l)
        alter=$(( ( $(date +%s) - $(stat -c %Y "$wt" 2>/dev/null || date +%s) ) / 86400 ))
        printf 'gemergt=%-4s geaendert=%-3s alter=%3sd  %s\n' "$m" "$schmutz" "$alter" "$wt"
      done | sort
fi

abschnitt "System (ohne root lesbar)"
journalctl --disk-usage 2>/dev/null
groesse /var/log /var/cache /tmp
groesse /tmp/* | head -8
command -v flatpak >/dev/null && { echo "Flatpak ungenutzt:"; flatpak list --unused --columns=application 2>/dev/null | head; }
