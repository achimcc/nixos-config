# Test fuer hs-riegel (checks.x86_64-linux.hs-riegel): Der Riegel muss ROT
# werden koennen, und die Renovate-Ausnahme darf nur genau das durchlassen,
# wofuer sie da ist. Wegwerf-Schluessel, Wegwerf-Repos, kein Netz:
#   - ein SSH-Schluessel ist UNSER Anker, ein zweiter ist fremd,
#   - ein GPG-Schluessel spielt GitHubs web-flow-Schluessel,
#   - die Herkunftspruefung (gh api compare) ersetzt ein Skript, das eine
#     Liste von „Fork-Revs" kennt.
# Dazu die Hook-Regel (deny/allow) und der ssh_config-Filter von hs-deploy.
set -uo pipefail
t=$(mktemp -d)
export HOME="$t/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
ssh-keygen -q -t ed25519 -N '' -C gut -f "$t/gut"
ssh-keygen -q -t ed25519 -N '' -C fremd -f "$t/fremd"
printf 'test@example.invalid namespaces="git" %s\n' "$(cat "$t/gut.pub")" >"$t/anker"

export GNUPGHOME="$t/gh"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'GitHub <noreply@github.com>' ed25519 sign never 2>/dev/null
ghfpr=$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ {print $10; exit}')
gpg --batch --armor --export "$ghfpr" >"$t/gh.asc"

printf '#!%s\ngrep -qx "$4" "%s" && exit 1\nexit 0\n' "$BASH" "$t/fork_revs" >"$t/herkunft"
chmod +x "$t/herkunft"
: >"$t/fork_revs"

export HS_RIEGEL_ANKER="$t/anker" HS_RIEGEL_KLONE="$t/klone" \
  HS_RIEGEL_GITHUB_SCHLUESSEL="$t/gh.asc" HS_RIEGEL_GITHUB_FPR="$ghfpr" \
  HS_RIEGEL_HERKUNFT="$t/herkunft"

neu_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config gpg.format ssh
  git -C "$1" config user.signingkey "$t/gut"
  git -C "$1" config commit.gpgsign true
}
# Eigener Commit (SSH-signiert mit unserem Schluessel); weitere git -c ... davor.
eigen() { # <repo> <text> [git -c ...]
  local r=$1 text=$2
  shift 2
  git -C "$r" add -A
  git -C "$r" "$@" commit -q --allow-empty -m "$text"
}
# Ein Commit, wie GitHubs Weboberflaeche oder API ihn anlegt: GPG-signiert
# mit „GitHubs" Schluessel, Committer GitHub.
github() { # <repo> <autor> <text> [git commit ...]
  local r=$1 autor=$2 text=$3
  shift 3
  git -C "$r" add -A
  GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com \
    git -C "$r" -c gpg.format=openpgp -c user.signingkey="$ghfpr" -c gpg.program=gpg \
    commit -q -S --author="$autor" -m "$text" "$@"
}
RENOVATE='renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>'

lock() { # <repo> <werkzeug-rev> <nixpkgs-owner> <nixpkgs-rev> [narHash]
  cat >"$1/flake.lock" <<EOF
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1700000000,
        "narHash": "${5:-sha256-alt}",
        "owner": "$3",
        "repo": "nixpkgs",
        "rev": "$4",
        "type": "github"
      },
      "original": { "owner": "NixOS", "ref": "nixos-unstable", "repo": "nixpkgs", "type": "github" }
    },
    "werkzeug": {
      "locked": { "owner": "achimcc", "repo": "werkzeug", "rev": "$2", "type": "github" },
      "original": { "owner": "achimcc", "repo": "werkzeug", "type": "github" }
    },
    "root": { "inputs": { "nixpkgs": "nixpkgs", "werkzeug": "werkzeug" } }
  },
  "root": "root",
  "version": 7
}
EOF
}
rev1=1111111111111111111111111111111111111111
rev2=2222222222222222222222222222222222222222
revfork=3333333333333333333333333333333333333333
echo "$revfork" >"$t/fork_revs"
dig1=sha256:$(printf 'a%.0s' {1..64})
dig2=sha256:$(printf 'b%.0s' {1..64})

mkdir -p "$t/klone"
neu_repo "$t/klone/werkzeug"
eigen "$t/klone/werkzeug" w1
w1=$(git -C "$t/klone/werkzeug" rev-parse HEAD)

r="$t/repo"
neu_repo "$r"
mkdir -p "$r/hosts/server" "$r/.github/workflows" "$r/pkgs/p"
lock "$r" "$w1" NixOS "$rev1"
cat >"$r/hosts/server/x.nix" <<EOF
{
  image = "docker.io/foo/bar:1.0@$dig1";
  port = 8080;
}
EOF
cat >"$r/.github/workflows/ci.yml" <<'EOF'
jobs:
  a:
    steps:
      - uses: actions/checkout@v4 # v4.0.0
EOF
cat >"$r/pkgs/p/Cargo.toml" <<'EOF'
[package]
name = "p"
version = "0.1.0"

[dependencies]
serde = "1.0.1"
EOF
echo start >"$r/datei"
eigen "$r" basis
basis=$(git -C "$r" rev-parse HEAD)
git -C "$r" branch -q sauber

fehler=0
faelle=0
erwarte() { # <erwarteter exit> <name> [basis]
  local soll=$1 name=$2 b=${3:-$basis}
  hs-riegel pruefen "$r" "$b" HEAD >"$t/aus" 2>&1
  local ist=$?
  faelle=$((faelle + 1))
  if [ "$ist" -eq "$soll" ]; then
    echo "ok     $name (exit $ist)"
  else
    echo "FEHLER $name: exit $ist statt $soll"
    sed 's/^/       /' "$t/aus"
    fehler=$((fehler + 1))
  fi
}
zurueck() {
  git -C "$r" checkout -q -f main
  git -C "$r" reset -q --hard sauber
  git -C "$r" branch -q -D renovate/wartung 2>/dev/null || true
}

# --- a) eigene Signatur --------------------------------------------------------
echo mehr >>"$r/datei"
eigen "$r" signiert
erwarte 0 "eigener signierter Commit"
zurueck

echo mehr >>"$r/datei"
eigen "$r" unsigniert -c commit.gpgsign=false
erwarte 1 "unsignierter Commit"
zurueck

echo mehr >>"$r/datei"
eigen "$r" fremd -c user.signingkey="$t/fremd"
erwarte 1 "fremder SSH-Schluessel"
zurueck

git -C "$r" checkout -q -b seite
echo seite >>"$r/datei"
eigen "$r" "unsigniert im Seitenzweig" -c commit.gpgsign=false
git -C "$r" checkout -q main
git -C "$r" merge -q --no-ff -m "signierter Merge" seite
erwarte 1 "signierter Merge zieht Unsigniertes herein"
zurueck
git -C "$r" branch -q -D seite

# --- b) die Renovate-Ausnahme -----------------------------------------------
lock "$r" "$w1" NixOS "$rev2" sha256-neu
github "$r" "$RENOVATE" "chore(deps): nixpkgs"
erwarte 0 "GitHub-signierter Renovate-Commit, nur flake.lock-Rev"
zurueck

lock "$r" "$w1" angreifer "$rev2" sha256-neu
github "$r" "$RENOVATE" "chore(deps): nixpkgs"
erwarte 1 "derselbe mit geaendertem owner"
zurueck

lock "$r" "$w1" NixOS "$revfork" sha256-neu
github "$r" "$RENOVATE" "chore(deps): nixpkgs"
erwarte 1 "Renovate-Rev nur im Fork-Netz, nicht auf dem Zweig"
zurueck

sed -i "s|bar:1.0@$dig1|bar:1.1@$dig2|" "$r/hosts/server/x.nix"
github "$r" "$RENOVATE" "chore(deps): bar"
erwarte 0 "Renovate-Commit hebt Image-Tag und Digest"
zurueck

sed -i "s|docker.io/foo/bar:1.0@$dig1|docker.io/boese/bar:1.0@$dig2|" "$r/hosts/server/x.nix"
github "$r" "$RENOVATE" "chore(deps): bar"
erwarte 1 "Renovate-Commit tauscht den Image-Namen"
zurueck

sed -i 's|port = 8080;|port = 22;|' "$r/hosts/server/x.nix"
github "$r" "$RENOVATE" "chore(deps): bar"
erwarte 1 "Renovate-Commit mit Nicht-Image-Zeile in hosts/"
zurueck

sed -i 's|checkout@v4 # v4.0.0|checkout@0123456789abcdef0123456789abcdef01234567 # v4.1.0|' "$r/.github/workflows/ci.yml"
github "$r" "$RENOVATE" "chore(deps): checkout"
erwarte 0 "Renovate-Commit pinnt uses: auf Digest"
zurueck

sed -i 's|actions/checkout@v4|boese/checkout@v4|' "$r/.github/workflows/ci.yml"
github "$r" "$RENOVATE" "chore(deps): checkout"
erwarte 1 "Renovate-Commit tauscht die Action"
zurueck

sed -i 's|serde = "1.0.1"|serde = "1.0.2"|; s|^version = "0.1.0"|version = "0.1.1"|' "$r/pkgs/p/Cargo.toml"
github "$r" "$RENOVATE" "chore(deps): serde"
erwarte 0 "Renovate-Commit hebt nur Cargo-Versionen"
zurueck

sed -i 's|serde = "1.0.1"|serde = { git = "https://example.invalid/serde" }|' "$r/pkgs/p/Cargo.toml"
github "$r" "$RENOVATE" "chore(deps): serde"
erwarte 1 "Renovate-Commit macht aus der Version eine git-Quelle"
zurueck

lock "$r" "$w1" NixOS "$rev2" sha256-neu
echo '{ }' >"$r/flake.nix"
github "$r" "$RENOVATE" "chore(deps): nixpkgs"
erwarte 1 "Renovate-Commit legt flake.nix an"
zurueck

lock "$r" "$w1" NixOS "$rev2" sha256-neu
github "$r" "test <test@example.invalid>" "nixpkgs heben"
erwarte 1 "GitHub-signiert mit anderem Autor (Token-Diebstahl)"
zurueck

lock "$r" "$w1" NixOS "$rev2" sha256-neu
git -C "$r" add -A
git -C "$r" -c gpg.format=openpgp -c user.signingkey="$ghfpr" -c gpg.program=gpg \
  commit -q -S --author="$RENOVATE" -m "chore(deps): nixpkgs"
erwarte 1 "GitHub-signiert, Renovate-Autor, Committer nicht GitHub"
zurueck

# Der Web-Merge: renovate/wartung zweigt ab, main laeuft mit einem eigenen
# Commit weiter, GitHubs Merge-Knopf fuehrt beide zusammen.
web_merge_vorbereiten() {
  git -C "$r" checkout -q -b renovate/wartung sauber
  lock "$r" "$w1" NixOS "$rev2" sha256-neu
  github "$r" "$RENOVATE" "chore(deps): Wartungsfenster"
  git -C "$r" checkout -q main
  echo weiter >>"$r/datei"
  eigen "$r" "main laeuft weiter"
  git -C "$r" merge -q --no-ff --no-commit renovate/wartung
}
web_merge_vorbereiten
github "$r" "test <test@example.invalid>" "Merge pull request #7 from achimcc/renovate/wartung"
erwarte 0 "Web-Merge eines renovate/-Zweigs ohne Zusatzinhalt"
zurueck

web_merge_vorbereiten
sed -i 's|checkout@v4 # v4.0.0|checkout@v5 # v5.0.0|' "$r/.github/workflows/ci.yml"
github "$r" "test <test@example.invalid>" "Merge pull request #7 from achimcc/renovate/wartung"
erwarte 1 "derselbe Merge mit Zusatzdatei"
zurueck

web_merge_vorbereiten
github "$r" "test <test@example.invalid>" "Merge pull request #7 from angreifer/renovate/wartung"
erwarte 1 "Web-Merge aus fremdem Zweig"
zurueck

# --- c) eigene Eingaenge ------------------------------------------------------
eigen "$t/klone/werkzeug" w2 -c commit.gpgsign=false
w2=$(git -C "$t/klone/werkzeug" rev-parse HEAD)
eigen "$t/klone/werkzeug" w3
w3=$(git -C "$t/klone/werkzeug" rev-parse HEAD)

lock "$r" "$w2" NixOS "$rev1"
eigen "$r" "Eingang gehoben"
erwarte 1 "eigener Eingang mit unsigniertem Rev"
zurueck

lock "$r" "$w3" NixOS "$rev1"
github "$r" "$RENOVATE" "chore(deps): werkzeug"
erwarte 1 "Renovate hebt eigenen Eingang ueber einen unsignierten Rev"
zurueck

git -C "$t/klone/werkzeug" reset -q --hard "$w1"
eigen "$t/klone/werkzeug" w4
w4=$(git -C "$t/klone/werkzeug" rev-parse HEAD)
lock "$r" "$w4" NixOS "$rev1"
github "$r" "$RENOVATE" "chore(deps): werkzeug"
erwarte 0 "Renovate hebt eigenen Eingang auf signierten Rev"
zurueck

# --- 2: keine Aussage ----------------------------------------------------------
echo mehr >>"$r/datei"
eigen "$r" signiert
HS_RIEGEL_ANKER="$t/gibtesnicht" erwarte 2 "kein Vertrauensanker"
erwarte 2 "laufender Stand im Repo unbekannt" 4444444444444444444444444444444444444444
zurueck

# --- Die Hook-Regel -----------------------------------------------------------
hook() { # <soll: deny|allow> <kommando>
  local soll=$1 cmd=$2 aus ist
  aus=$(jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}' | hs-riegel hook claude)
  if [ -z "$aus" ]; then
    ist=allow
  else
    ist=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$aus")
  fi
  faelle=$((faelle + 1))
  if [ "$ist" = "$soll" ]; then
    echo "ok     Hook $soll: $cmd"
  else
    echo "FEHLER Hook: $ist statt $soll: $cmd"
    fehler=$((fehler + 1))
  fi
}
hook deny 'just deploy'
hook deny 'just deploy test'
hook deny 'just deploy-vps'
hook deny 'nix develop --command just deploy'
hook deny 'VERLUST_OK=1 just deploy'
hook deny './scripts/deploy.sh server'
hook deny 'bash scripts/deploy.sh vps'
hook deny 'cd /w && scripts/deploy.sh server'
hook deny 'cd scripts && ./deploy.sh server'
hook deny 'nix run .#colmena -- apply --on server'
hook deny 'colmena apply switch'
hook deny "lotse run --class=deploy --target server -- bash -c 'cd /w && just deploy'"
hook deny 'hs-deploy server && just deploy'
hook allow 'hs-deploy server'
hook allow 'hs-deploy vps test'
hook allow "lotse run --class=deploy --target server --max-wait 3h -- bash -c 'cd /w && git fetch origin && git merge origin/main --no-edit && git push origin HEAD:main && hs-deploy server'"
hook allow 'just deploy-diff'
hook allow 'just deploy-bauen'
hook allow 'just smoke'
hook allow 'cat scripts/deploy.sh'
hook allow 'git show origin/main:scripts/deploy.sh'
hook allow 'sed -n 1,20p scripts/deploy.sh'
hook allow 'nix run .#colmena -- build'
hook allow 'ls -la'

# --- Der ssh_config-Filter von hs-deploy --------------------------------------
cat >"$t/ssh_config" <<'EOF'
# Kommentar
Host vps 1.2.3.4
    User root
    Port 22022
    ProxyCommand sh -c 'touch /tmp/boese'
    UserKnownHostsFile ~/repo/boese_known_hosts
    StrictHostKeyChecking no
    IdentitiesOnly yes
Match host server user root
    IdentityFile ~/.ssh/id_ecdsa.pub
EOF
faelle=$((faelle + 1))
if gefiltert=$(hs-deploy-ssh-filter <"$t/ssh_config" 2>/dev/null) \
  && ! grep -qiE 'proxycommand|userknownhostsfile|stricthostkeychecking' <<<"$gefiltert" \
  && grep -q '^port 22022$' <<<"$gefiltert" && grep -q '^match host server user root$' <<<"$gefiltert"; then
  echo "ok     ssh_config-Filter verwirft ProxyCommand, UserKnownHostsFile, StrictHostKeyChecking"
else
  echo "FEHLER ssh_config-Filter"
  fehler=$((fehler + 1))
fi
faelle=$((faelle + 1))
if printf 'Match exec "touch /tmp/boese"\n  User root\n' | hs-deploy-ssh-filter >/dev/null 2>&1; then
  echo "FEHLER ssh_config-Filter laesst Match exec durch"
  fehler=$((fehler + 1))
else
  echo "ok     ssh_config-Filter lehnt Match exec ab"
fi

gpgconf --kill all 2>/dev/null || true
rm -rf "$t"
if [ "$fehler" -gt 0 ]; then
  echo "$fehler von $faelle Faellen falsch — der Riegel haelt nicht, was er verspricht." >&2
  exit 1
fi
echo "hs-riegel: $faelle von $faelle Faellen wie erwartet."
