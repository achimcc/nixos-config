# hs-riegel — der Signatur-Riegel fuer Homeserver-Deploys, AUSSERHALB des
# geprueften Repos. (Vorgaenger und Vorbild: scripts/signaturen-pruefen.sh im
# homeserver-Repo, Audit 3, B76/B101.)
#
# WARUM HIER UND NICHT IM REPO: Ein Pruefer, der im geprueften Repo liegt,
# wird von genau dem Angreifer mitgeaendert, gegen den er pruefen soll — wer
# Push-Recht auf `main` erbeutet, schreibt `exit 0` in denselben Commit.
# homeserver ist privat auf GitHub Free: kein Branch-Schutz, keine Pflicht zu
# Signaturen. Dieser Pruefer liegt deshalb in ~/nixos-config, und `hs-deploy`
# ruft ihn VOR `just deploy` auf.
#
# DREI FRAGEN je Commit in <basis>..<ziel> (alle, auch hereingemergte):
#   a) Gueltig signiert mit einem Schluessel aus ~/.ssh/allowed_signers? -> ok
#   b) Sonst NUR ok, wenn gueltig von GitHubs web-flow-Schluessel signiert
#      (gepinnt, eigener GNUPGHOME nur mit ihm) UND Renovate-foermig:
#        - Autor renovate[bot] und Committer GitHub (Renovates API-Commits,
#          Squash- und Rebase-Merges ueber die Weboberflaeche), oder
#        - ein Web-Merge `Merge pull request #n from achimcc/renovate/…` mit
#          genau zwei Eltern, der keine Datei aendert, die nicht schon auf der
#          Seite des zweiten Elters geaendert wurde,
#      UND jede Aenderung (gegen den ersten Elter) liegt in der Erlaubnisliste
#      (inhalt.py): flake.lock nur Revs, Workflows nur `uses:`, Images nur
#      Tag/Digest, Cargo nur Versionen. Ein neuer flake.lock-Rev muss auf dem
#      Zweig des Originals liegen (GitHub liefert auch Commits aus Forks unter
#      dem Namen des Originals aus).
#   c) Jeder eigene Flake-Eingang (achimcc), dessen Rev sich aendert: alle
#      Commits alt..neu im lokalen Klon ~/Projects/<repo> von UNS signiert —
#      ohne GitHub-Ausnahme.
#
# WARUM NICHT EINFACH GITHUBS SCHLUESSEL VERTRAUEN: GitHub signiert JEDEN
# Commit, der ueber Weboberflaeche oder API entsteht — auch den eines
# Token-Diebs. Der Autor ist dabei frei waehlbar; was einen Dieb begrenzt, ist
# allein die Erlaubnisliste. Deshalb ist sie eng.
#
# Aufruf: hs-riegel pruefen <repo> <basis-rev> [<ziel-rev>=HEAD]
#         hs-riegel hook claude      (PreToolUse-Hook, s. modules/hs-riegel.nix)
# Exit 0: alles belegt. 1: mindestens ein Befund. 2: Werkzeugfehler — haelt
#         den Deploy ebenfalls an: Wer nicht pruefen kann, kann nicht freigeben.
#
# Test-Overrides (checks.hs-riegel), KEINE Umgehung — die Voreinstellungen
# zeigen auf die echten Orte:
#   HS_RIEGEL_ANKER        allowed_signers      (~/.ssh/allowed_signers)
#   HS_RIEGEL_KLONE        Klone der Eingaenge  (~/Projects)
#   HS_RIEGEL_GITHUB_SCHLUESSEL / HS_RIEGEL_GITHUB_FPR   (web-flow, gepinnt)
#   HS_RIEGEL_HERKUNFT     Programm <owner> <repo> <ref> <rev> -> 0 auf dem
#                          Zweig, 1 nicht, sonst Fehler (gh api compare)

RENOVATE_NAME='renovate[bot]'
RENOVATE_MAIL='29139614+renovate[bot]@users.noreply.github.com'
GITHUB_COMMITTER='GitHub <noreply@github.com>'

rot() { printf '   \033[31m%s\033[0m\n' "$*"; }

# --- Der Hook fuer Claude-Code-Sitzungen ---------------------------------------
#
# Lehnt ein Bash-Kommando ab, das den Homeserver an `hs-deploy` vorbei
# ausrollt. Ein Kommando, das nichts davon enthaelt, bekommt KEINE Entscheidung
# (kein Output) und laeuft durch den normalen Freigabeweg — der Hook erzwingt
# keine Rueckfrage.
#
# Die Muster verlangen die Kommandostellung (Anfang, nach ; & | ( ` ' " oder
# Leerraum) und treffen damit auch Text in Anfuehrungszeichen, etwa ein
# `grep "just deploy"`. Das ist gewollt: Ein falscher Treffer kostet eine
# umformulierte Suche, ein fehlender einen Deploy am Riegel vorbei.
hs_deploy_muster=(
  # just deploy / just deploy-vps, auch mit Optionen dazwischen (just -f x deploy)
  "(^|[;&|(\`'\"[:space:]/])just([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+deploy(-vps)?([;&|)\`'\"[:space:]]|\$)"
  # scripts/deploy.sh am Kommandoanfang oder hinter bash/sh/exec/env/…
  "(^|[;&|(\`'\"]|(^|[^[:alnum:]_-])(bash|sh|exec|env|nohup|setsid|sudo|timeout|nice|command)([[:space:]]+[^;&|[:space:]]+)*[[:space:]])[[:space:]]*[^;&|[:space:]'\"]*scripts/deploy\\.sh([;&|)\`'\"[:space:]]|\$)"
  # ./deploy.sh aus scripts/ heraus
  "(^|[;&|(\`'\"[:space:]])\\./deploy\\.sh([;&|)\`'\"[:space:]]|\$)"
  # colmena apply, auch nix run .#colmena -- apply
  "(^|[^[:alnum:]_-])colmena([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+apply([;&|)\`'\"[:space:]]|\$)"
)

hook_claude() {
  local eingabe cmd m
  eingabe=$(cat)
  cmd=$(jq -r '.tool_input.command // empty' <<<"$eingabe" 2>/dev/null) || exit 0
  [ -n "$cmd" ] || exit 0
  for m in "${hs_deploy_muster[@]}"; do
    if grep -qE -- "$m" <<<"$cmd"; then
      jq -n --arg grund "hs-riegel: Homeserver-Deploys laufen nur ueber 'hs-deploy [server|vps] [Argumente fuer just deploy]'. hs-deploy prueft vorher mit einem Pruefer AUSSERHALB des Repos (~/nixos-config), dass jeder Commit seit dem laufenden Stand von uns signiert ist (oder ein eng umrissener Renovate-Commit von GitHub), und startet erst dann 'just deploy'. Im Deploy-Slot: lotse run --class=deploy --target server --max-wait 3h -- bash -c 'cd <worktree> && git fetch origin && git merge origin/main --no-edit && git push origin HEAD:main && hs-deploy server'. Trifft die Regel nur Text (Suchmuster, Commit-Nachricht), das Leerzeichen als [[:space:]] schreiben." \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $grund}}'
      exit 0
    fi
  done
  exit 0
}

# --- Der Pruefer -------------------------------------------------------------

pruefen() {
  local repo=${1:?Aufruf: hs-riegel pruefen <repo> <basis-rev> [<ziel-rev>]}
  local basis=${2:?Basis-Rev fehlt}
  local ziel_arg=${3:-HEAD}
  local anker=${HS_RIEGEL_ANKER:-$HOME/.ssh/allowed_signers}
  local klone=${HS_RIEGEL_KLONE:-$HOME/Projects}
  local gh_schluessel=${HS_RIEGEL_GITHUB_SCHLUESSEL:-$webflow_schluessel_datei}
  local gh_fpr=${HS_RIEGEL_GITHUB_FPR:-$webflow_fpr}

  if [ ! -r "$anker" ] || [ ! -s "$anker" ]; then
    echo "hs-riegel: kein Vertrauensanker unter $anker — ohne ihn keine Aussage." >&2
    return 2
  fi

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  # Zwei GNUPGHOMEs: ein LEERER fuer Frage a) — sonst zaehlte ein GPG-Schluessel
  # aus Achims eigenem Schluesselbund als „von uns" — und einer NUR mit GitHubs
  # web-flow-Schluessel fuer Frage b).
  mkdir -m 700 "$tmp/leer" "$tmp/github"
  : >"$tmp/keine_signer"
  if ! GNUPGHOME="$tmp/github" gpg --batch --quiet --import "$gh_schluessel" 2>/dev/null; then
    echo "hs-riegel: GitHubs Schluessel aus $gh_schluessel nicht importierbar." >&2
    return 2
  fi
  if ! GNUPGHOME="$tmp/github" gpg --batch --with-colons --fingerprint 2>/dev/null \
    | grep -q "^fpr:::::::::$gh_fpr:\$"; then
    echo "hs-riegel: im gepinnten GitHub-Schluessel fehlt der Fingerabdruck $gh_fpr." >&2
    return 2
  fi
  printf '%s:6:\n' "$gh_fpr" | GNUPGHOME="$tmp/github" gpg --batch --quiet --import-ownertrust 2>/dev/null

  # Jede Einstellung, die die Pruefung beeinflusst, kommt von hier — nicht aus
  # ~/.gitconfig und nicht aus .git/config des Repos.
  uns() {
    GNUPGHOME="$tmp/leer" git -C "$1" -c gpg.program=gpg -c gpg.ssh.program=ssh-keygen \
      -c gpg.ssh.allowedSignersFile="$anker" -c log.showSignature=false "${@:2}"
  }
  github() {
    GNUPGHOME="$tmp/github" git -C "$1" -c gpg.program=gpg -c gpg.ssh.program=ssh-keygen \
      -c gpg.ssh.allowedSignersFile="$tmp/keine_signer" -c log.showSignature=false "${@:2}"
  }

  local ziel
  if ! ziel=$(git -C "$repo" rev-parse --verify --quiet "$ziel_arg^{commit}"); then
    echo "hs-riegel: Ziel $ziel_arg ist in $repo unbekannt." >&2
    return 2
  fi

  # Liste der zu pruefenden Commits eines Bereichs: alles, was vom Ziel aus
  # erreichbar ist und vom Basis-Stand aus nicht — damit auch jeder Commit
  # eines Seitenzweigs, den ein Merge hereinzieht. Ist das Ziel kein
  # Nachfolger (Rollback), gilt zusaetzlich das Ziel selbst.
  commits_von() { # <wo> <alt> <neu> -> Revs, eine je Zeile
    local wo=$1 alt=$2 neu=$3
    if [ -n "$alt" ]; then
      git -C "$wo" rev-list "$alt..$neu" || return 2
      git -C "$wo" merge-base --is-ancestor "$alt" "$neu" 2>/dev/null || echo "$neu"
    else
      echo "$neu"
    fi
  }

  local befunde=0

  # --- a) und b): das homeserver-Repo selbst ------------------------------------
  if ! git -C "$repo" cat-file -e "$basis^{commit}" 2>/dev/null; then
    echo "hs-riegel: laufender Stand ${basis:0:12} ist in $repo unbekannt (git fetch origin?) — keine Aussage." >&2
    return 2
  fi
  basis=$(git -C "$repo" rev-parse "$basis^{commit}")
  local liste
  liste=$(commits_von "$repo" "$basis" "$ziel" | sort -u) || return 2

  local c st zeilen="" fremde=0 gh=0
  while read -r c; do
    [ -n "$c" ] || continue
    st=$(uns "$repo" log -1 --format='%G?' "$c") || return 2
    [ "$st" = G ] && continue
    if renovate_pruefen "$repo" "$c"; then
      gh=$((gh + 1))
      continue
    else
      local rc=$?
      [ "$rc" -eq 2 ] && return 2
    fi
    fremde=$((fremde + 1))
    zeilen+="$(uns "$repo" log -1 --format='%G? %h %an <%ae>: %s' "$c")"$'\n'
    [ -s "$tmp/grund" ] && zeilen+="$(sed 's/^/       /' "$tmp/grund")"$'\n'
  done <<<"$liste"
  if [ "$fremde" -gt 0 ]; then
    rot "homeserver: $fremde Commit(s) ohne unsere Signatur und ohne gueltige Renovate-Ausnahme:"
    printf '%s' "$zeilen" | head -40 | sed 's/^/     /'
    befunde=$((befunde + 1))
  fi

  # --- c): die eigenen Flake-Eingaenge ------------------------------------------
  eingaenge() {
    git -C "$repo" show "$1:flake.lock" 2>/dev/null | jq -r '
      .nodes | to_entries[]
      | select(.value.locked? != null)
      | .value.locked as $l
      | select(($l.owner // "") == "achimcc" or (($l.url // "") | test("achimcc/")))
      | "\($l.repo // ($l.url | sub(".*/"; "") | sub("\\.git.*"; "") | sub("\\?.*"; "")))\t\($l.rev)"' | sort -u
  }
  declare -A alt_rev=()
  local r v
  while IFS=$'\t' read -r r v; do [ -n "$r" ] && alt_rev[$r]=$v; done < <(eingaenge "$basis")
  local neu_liste
  neu_liste=$(eingaenge "$ziel")
  if [ -z "$neu_liste" ]; then
    echo "hs-riegel: im flake.lock des Ziels steht kein eigener Eingang — das Suchmuster ist tot, nicht der Stand sauber." >&2
    return 2
  fi
  local geprueft=0 klon eliste
  while IFS=$'\t' read -r r v; do
    [ -n "$r" ] || continue
    [ "${alt_rev[$r]:-}" = "$v" ] && continue
    klon="$klone/$r"
    if [ ! -e "$klon/.git" ]; then
      echo "hs-riegel: Eingang $r hat sich geaendert, aber es gibt keinen Klon unter $klon." >&2
      return 2
    fi
    # MIT FRIST (2026-10-01): Derselbe Abruf in `scripts/signaturen-pruefen.sh`
    # des homeserver-Repos hing 1 h 51 min an einer toten Verbindung zu GitHub
    # und hielt so lange den Deploy-Slot aller Sitzungen. Verstreicht die
    # Frist, zaehlt der lokale Klon - fehlt dort der Rev, endet es mit 2.
    timeout "${HS_RIEGEL_FETCH_FRIST:-120}" git -C "$klon" fetch --quiet --tags origin 2>/dev/null || true
    if ! git -C "$klon" cat-file -e "$v^{commit}" 2>/dev/null; then
      echo "hs-riegel: Eingang $r: Rev ${v:0:12} ist im Klon $klon unbekannt." >&2
      return 2
    fi
    local alt=${alt_rev[$r]:-}
    git -C "$klon" cat-file -e "$alt^{commit}" 2>/dev/null || alt=""
    eliste=$(commits_von "$klon" "$alt" "$v" | sort -u) || return 2
    zeilen=""
    while read -r c; do
      [ -n "$c" ] || continue
      st=$(uns "$klon" log -1 --format='%G?' "$c") || return 2
      [ "$st" = G ] || zeilen+="$(uns "$klon" log -1 --format='%G? %h %an: %s' "$c")"$'\n'
    done <<<"$eliste"
    if [ -n "$zeilen" ]; then
      rot "Eingang $r: Commit(s) ohne gueltige Signatur aus $anker:"
      printf '%s' "$zeilen" | head -10 | sed 's/^/     /'
      befunde=$((befunde + 1))
    fi
    geprueft=$((geprueft + 1))
  done <<<"$neu_liste"

  if [ "$befunde" -gt 0 ]; then
    rot "ABBRUCH: $befunde Stelle(n) mit Commits ohne unsere Signatur."
    printf '   Kein Branch-Schutz auf GitHub (privat, Free) — dieser Riegel ist der einzige.\n'
    printf '   Stammt der Commit von uns: neu signieren. Ein Renovate-PR ausserhalb der\n'
    printf '   Erlaubnisliste: lokal pruefen, git merge --squash, signiert committen.\n'
    printf '   Stammt er nicht von uns: NICHT ausrollen, docs/runbooks/vorfall.md.\n'
    return 1
  fi
  printf '   hs-riegel: alle Commits seit %s belegt (%s ueber die Renovate-Ausnahme), %s geaenderte(r) Eingang/Eingaenge geprueft.\n' \
    "${basis:0:12}" "$gh" "$geprueft"
  return 0
}

# b) fuer einen Commit. 0 = zulaessig, 1 = nicht (Grund in $tmp/grund), 2 = Fehler.
renovate_pruefen() {
  local repo=$1 c=$2 st fpr prim an ae cn ce eltern msg aus rc
  : >"$tmp/grund"
  IFS=$'\x1f' read -r st fpr prim an ae cn ce eltern msg < <(
    github "$repo" log -1 --format=$'%G?\x1f%GF\x1f%GP\x1f%an\x1f%ae\x1f%cn\x1f%ce\x1f%P\x1f%s' "$c"
  ) || return 2
  if [ "$st" != G ] || { [ "$fpr" != "$gh_fpr" ] && [ "$prim" != "$gh_fpr" ]; }; then
    return 1
  fi
  if [ "$cn <$ce>" != "$GITHUB_COMMITTER" ]; then
    echo "GitHub-signiert, aber Committer ist nicht GitHub" >"$tmp/grund"
    return 1
  fi
  local -a e
  read -r -a e <<<"$eltern"
  if [ "${#e[@]}" -lt 1 ]; then
    echo "GitHub-signiert, aber ohne Elter" >"$tmp/grund"
    return 1
  fi
  if [ "$an" = "$RENOVATE_NAME" ] && [ "$ae" = "$RENOVATE_MAIL" ]; then
    :
  elif [ "${#e[@]}" -eq 2 ] && [[ $msg =~ ^Merge\ pull\ request\ \#[0-9]+\ from\ achimcc/renovate/[^[:space:]]+$ ]]; then
    # Kein Zusatzinhalt im Merge: jede Datei, die er gegen den ersten Elter
    # aendert, wurde auch auf der Seite des zweiten geaendert.
    local mb extra
    mb=$(git -C "$repo" merge-base "${e[0]}" "${e[1]}") || return 2
    extra=$(comm -23 \
      <(git -C "$repo" diff --name-only --no-renames "${e[0]}" "$c" | sort -u) \
      <(git -C "$repo" diff --name-only --no-renames "$mb" "${e[1]}" | sort -u))
    if [ -n "$extra" ]; then
      printf 'Web-Merge mit Zusatzinhalt:\n%s\n' "$extra" >"$tmp/grund"
      return 1
    fi
  else
    echo "GitHub-signiert, aber weder Renovate-Autor noch Web-Merge eines renovate/-Zweigs ($an <$ae>)" >"$tmp/grund"
    return 1
  fi

  aus=$(python3 "$inhalt_py" "$repo" "${e[0]}" "$c")
  rc=$?
  [ "$rc" -ge 2 ] && return 2
  if [ "$rc" -ne 0 ]; then
    grep -v '^HERKUNFT' <<<"$aus" >"$tmp/grund"
    return 1
  fi
  local o r ref rev
  while IFS=$'\t' read -r _ o r ref rev; do
    [ -n "$rev" ] || continue
    herkunft "$o" "$r" "$ref" "$rev"
    rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "flake.lock: $o/$r@${rev:0:12} liegt nicht auf dem Zweig ${ref} (Fork-Netz?)" >"$tmp/grund"
      return 1
    elif [ "$rc" -ne 0 ]; then
      echo "hs-riegel: Herkunft von $o/$r@${rev:0:12} nicht pruefbar." >&2
      return 2
    fi
  done < <(grep '^HERKUNFT' <<<"$aus")
  return 0
}

# Liegt <rev> auf dem Zweig <ref> (oder dem Standardzweig) von <owner>/<repo>?
# GitHub liefert unter github:<owner>/<repo>/<rev> auch Commits aus jedem Fork
# aus — ein Dieb koennte sonst einen Fork-Commit als nixpkgs-Rev eintragen.
herkunft() {
  local o=$1 r=$2 ref=$3 rev=$4 status
  if [ -n "${HS_RIEGEL_HERKUNFT:-}" ]; then
    "$HS_RIEGEL_HERKUNFT" "$o" "$r" "$ref" "$rev"
    return $?
  fi
  # Erst mit gh (angemeldet, hoeheres Limit), sonst anonym — die Eingaenge
  # sind oeffentlich, und ein abgelaufenes gh-Token soll den Riegel nicht
  # blind machen (am 2026-09-27 lieferte gh 401).
  api() {
    gh api "$1" --jq "$2" 2>/dev/null \
      || curl -fsS --max-time 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1" 2>/dev/null | jq -er "$2"
  }
  if [ "$ref" = - ]; then
    ref=$(api "repos/$o/$r" .default_branch) || return 2
  fi
  status=$(api "repos/$o/$r/compare/$ref...$rev" .status) || return 2
  case "$status" in
    behind | identical) return 0 ;;
    ahead | diverged) return 1 ;;
    *) return 2 ;;
  esac
}

case "${1:-}" in
  pruefen)
    shift
    pruefen "$@"
    exit $?
    ;;
  hook)
    [ "${2:-}" = claude ] || { echo "Aufruf: hs-riegel hook claude" >&2; exit 2; }
    hook_claude
    ;;
  *)
    echo "Aufruf: hs-riegel pruefen <repo> <basis-rev> [<ziel-rev>] | hs-riegel hook claude" >&2
    exit 2
    ;;
esac
