# hs-deploy — der EINZIGE Einstieg fuer Homeserver-Deploys aus einer
# Claude-Sitzung (der PreToolUse-Hook aus modules/hs-riegel.nix lehnt
# `just deploy`, `scripts/deploy.sh` und `colmena apply` ab).
#
# Aufruf, in einem Checkout von achimcc/homeserver:
#   hs-deploy [server|vps] [weitere Argumente fuer just deploy]
#
# 1. Liest den laufenden Stand des Ziels (`nixos-version
#    --configuration-revision`) ueber die ssh_config des Repos — der VPS NUR
#    so: MaxAuthTries 3, fail2ban, kein zweiter Zugangsweg.
# 2. `hs-riegel pruefen <repo> <laufend> HEAD` — der Pruefer aus
#    ~/nixos-config, nicht der im Repo.
# 3. Erst dann `nix develop <repo> --command just deploy|deploy-vps …`.
#
# DIE ssh_config KOMMT AUS DEM NOCH UNGEPRUEFTEN BAUM. Ungefiltert koennte ein
# Angreifer darin Code ausfuehren (ProxyCommand, LocalCommand, Match exec)
# oder den laufenden Stand faelschen (UserKnownHostsFile auf eine Datei im
# Repo, StrictHostKeyChecking no — dann antwortet SEIN Rechner mit einem Rev,
# der den Bereich leer macht). Deshalb geht nur eine gefilterte Kopie an ssh:
# Host, Match (host/user), HostName, User, Port, IdentityFile,
# IdentitiesOnly, HostKeyAlias. Die Hostschluessel kommen aus
# ~/.ssh/known_hosts und /etc/ssh/ssh_known_hosts.

ziel=${1:-server}
[ $# -gt 0 ] && shift
case "$ziel" in
  server) rezept=deploy ;;
  vps) rezept=deploy-vps ;;
  *)
    echo "hs-deploy: unbekanntes Ziel '$ziel' (server oder vps)" >&2
    exit 2
    ;;
esac

if ! repo=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "hs-deploy: kein Git-Checkout — hs-deploy laeuft in einem Checkout von achimcc/homeserver." >&2
  exit 2
fi
herkunft=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
if ! [[ $herkunft =~ [:/]achimcc/homeserver(\.git)?/?$ ]]; then
  echo "hs-deploy: origin von $repo ist nicht achimcc/homeserver ($herkunft)." >&2
  exit 2
fi
if [ ! -r "$repo/ssh_config" ]; then
  echo "hs-deploy: $repo/ssh_config fehlt." >&2
  exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! hs-deploy-ssh-filter <"$repo/ssh_config" >"$tmp/ssh_config"; then
  echo "hs-deploy: ssh_config enthaelt eine Match-Bedingung, die Code ausfuehren kann — kein Deploy." >&2
  exit 2
fi

ssh_opts=(-F "$tmp/ssh_config" -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR
  -o StrictHostKeyChecking=yes -o ProxyCommand=none -o ProxyJump=none
  -o PermitLocalCommand=no -o ControlMaster=no -o ControlPath=none)

printf '\n\033[1mhs-deploy: laufenden Stand auf %s lesen\033[0m\n' "$ziel"
laufend=$(timeout 60 ssh "${ssh_opts[@]}" "$ziel" nixos-version --configuration-revision 2>/dev/null)
laufend=${laufend%-dirty}
if ! [[ $laufend =~ ^[0-9a-f]{40}$ ]]; then
  printf '   \033[31mLaufender Stand auf %s nicht lesbar — keine Aussage, kein Deploy.\033[0m\n' "$ziel" >&2
  exit 2
fi
if ! git -C "$repo" cat-file -e "$laufend^{commit}" 2>/dev/null; then
  git -C "$repo" fetch --quiet origin 2>/dev/null || true
fi

kopf=$(git -C "$repo" rev-parse HEAD)
printf '\n\033[1mhs-deploy: Signaturen %s..%s pruefen\033[0m\n' "${laufend:0:12}" "${kopf:0:12}"
hs-riegel pruefen "$repo" "$laufend" "$kopf"
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '   \033[31mhs-deploy: Riegel sagt %s — kein Deploy.\033[0m\n' "$rc" >&2
  exit "$rc"
fi
if [ "$(git -C "$repo" rev-parse HEAD)" != "$kopf" ]; then
  echo "hs-deploy: HEAD hat sich waehrend der Pruefung bewegt — kein Deploy." >&2
  exit 1
fi
if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  printf '   \033[33mHinweis: ungestagte Aenderungen im Baum — sie sind nicht geprueft und rollen mit aus.\033[0m\n'
fi

cd "$repo" || exit 2
rm -rf "$tmp"
trap - EXIT
exec nix develop "$repo" --command just "$rezept" "$@"
