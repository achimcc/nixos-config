# vpn — einziger Umschaltpfad für die WireGuard-Slots (Tastenkürzel, Leiste, Terminal).
#
#   vpn 1…9      mit Slot n verbinden, andere Tunnel trennen, Wirkung prüfen
#   vpn aus      alle Tunnel trennen, "Direkt" beenden
#   vpn direkt   alle Tunnel trennen, Kill-Switch bewusst aus (Captive Portal)
#   vpn login    nach dem Login auf den zuletzt benutzten Slot wechseln
#   vpn status   gemessenen Zustand ausgeben
#
# Erfolg heißt: Die Exit-IP kam durch den Tunnel zurück. nmcli meldet bei WireGuard
# auch ohne Handshake Erfolg — das allein zählt nicht. Zwei Exit-IP-Dienste nacheinander,
# nicht nur einer: ein einzelner Dienst kann von einzelnen Exits aus gesperrt sein (gemessen
# 2026-09-13: am.i.mullvad.net antwortete von einem Slot aus mit Verbindungs-Timeout, obwohl
# der Tunnel selbst trug). Macht die Exit-Prüfung im ungünstigsten Fall 2 × 8 s = 16 s lang —
# bewusst 1 s über der 15-s-Grenze aus den globalen Randbedingungen.
# Exit-Codes: 0 belegt, 1 Tunnel trägt nicht, 2 Aufruffehler, 3 Umschaltung läuft.

server_json=/etc/vpn/server.json
status_json=/run/vpn/status.json
# Reihenfolge: erst Mullvad (liefert auch das Land), dann ipify als Rückfall (nur IP).
exit_dienste=(
  "https://am.i.mullvad.net/json"
  "https://api.ipify.org?format=json"
)
laufzeit="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR fehlt}/vpn"
zustand="${XDG_STATE_HOME:-$HOME/.local/state}/vpn"

melde() {
  # $1 Dringlichkeit (low|normal|critical), $2 Titel, $3 Text
  printf '%s: %s\n' "$2" "$3" >&2
  notify-send --app-name=VPN --urgency="$1" "$2" "$3" 2>/dev/null || true
}

sperre() {
  mkdir -p "$laufzeit"
  exec 9>"$laufzeit/lock"
  if ! flock -n 9; then
    melde normal "VPN" "Umschaltung läuft bereits."
    exit 3
  fi
}

aktive_tunnel() {
  nmcli -t -f NAME,TYPE connection show --active \
    | awk -F: '$2 == "wireguard" && $1 ~ /^wg-[1-9]$/ { print $1 }'
}

trenne_tunnel_ausser() {
  local behalten=${1:-} verbindung rest
  while read -r verbindung; do
    if [ -n "$verbindung" ] && [ "$verbindung" != "$behalten" ]; then
      # || true: ein bereits verschwundenes Profil darf das Skript nicht abbrechen —
      # gemessen wird danach, ob wirklich noch ein Tunnel läuft.
      nmcli connection down "$verbindung" >/dev/null || true
    fi
  done < <(aktive_tunnel)

  rest=$(aktive_tunnel | grep -v -x "$behalten" || true)
  if [ -n "$rest" ]; then
    melde critical "⚠ VPN" "Konnte $rest nicht trennen."
    exit 1
  fi
}

name_von() {
  jq -r --argjson s "$1" '[.[] | select(.slot == $s) | .name][0] // empty' "$server_json"
}

schreibe_exit() {
  # $1 Slot, $2 IP — atomar, damit die Leiste nie eine halbe Datei liest
  jq -n --argjson slot "$1" --arg ip "$2" --argjson zeit "$(date +%s)" \
    '{slot: $slot, ip: $ip, zeit: $zeit}' > "$laufzeit/exit.json.tmp"
  mv "$laufzeit/exit.json.tmp" "$laufzeit/exit.json"
}

verbinde() {
  local slot=$1 name verbindung antwort ip land dienst
  name=$(name_von "$slot")
  if [ -z "$name" ]; then
    echo "vpn: Slot $slot gibt es nicht" >&2
    exit 2
  fi
  verbindung="wg-$slot"

  trenne_tunnel_ausser "$verbindung"
  rm -f "$laufzeit/exit.json"

  if ! nmcli connection up "$verbindung" >/dev/null; then
    melde critical "⚠ VPN $name" "NetworkManager konnte $verbindung nicht aktivieren."
    exit 1
  fi

  ip=""
  land="?"
  for dienst in "${exit_dienste[@]}"; do
    if antwort=$(curl --silent --fail --max-time 8 --interface "$verbindung" "$dienst") \
      && ip=$(jq -er '.ip' <<<"$antwort"); then
      land=$(jq -r '.country // "?"' <<<"$antwort")
      break
    fi
  done

  if [ -n "$ip" ]; then
    schreibe_exit "$slot" "$ip"
    mkdir -p "$zustand"
    echo "$slot" > "$zustand/letzter"
    # Erst nach bestätigtem Tunnel: Scheitert er, bleibt "Direkt" bestehen.
    if ! systemctl stop vpn-direkt.service; then
      melde critical "⚠ VPN $name" "Tunnel steht, aber vpn-direkt ließ sich nicht stoppen."
      exit 1
    fi
    melde normal "🔒 VPN $name" "Exit $ip ($land)"
  else
    melde critical "⚠ VPN $name" "Kein Verkehr durch den Tunnel (Exit-IP nicht abrufbar, beide Dienste). Das Profil bleibt aktiv, WireGuard versucht es weiter."
    exit 1
  fi
}

aus() {
  trenne_tunnel_ausser ""
  rm -f "$laufzeit/exit.json"
  if ! systemctl stop vpn-direkt.service; then
    melde critical "⚠ VPN" "vpn-direkt ließ sich nicht stoppen — Zustand Direkt kann noch aktiv sein."
    exit 1
  fi
  melde normal "⛔ VPN aus" "Alle Tunnel getrennt."
}

direkt() {
  trenne_tunnel_ausser ""
  rm -f "$laufzeit/exit.json"
  # restart statt start: Nach einem nftables-Reload ist die Unit evtl. noch
  # "active", die Chain aber leer — start wäre dann wirkungslos.
  if ! systemctl restart vpn-direkt.service; then
    melde critical "⚠ VPN" "vpn-direkt ließ sich nicht starten — Kill-Switch bleibt an."
    exit 1
  fi
  melde critical "⚠ VPN DIREKT" "Kill-Switch aus, Verkehr ungeschützt — bis ein Server gewählt wird oder bis zum Neustart."
}

login() {
  local slot=1
  if [ -r "$zustand/letzter" ]; then
    slot=$(cat "$zustand/letzter")
  fi
  case "$slot" in
    [1-9]) ;;
    *) slot=1 ;;
  esac
  if [ "$(aktive_tunnel)" = "wg-$slot" ]; then
    exit 0
  fi
  verbinde "$slot"
}

zeige_status() {
  jq . "$status_json"
  if [ -r "$laufzeit/exit.json" ]; then
    jq . "$laufzeit/exit.json"
  fi
}

case "${1:-}" in
  [1-9]) sperre; verbinde "$1" ;;
  aus) sperre; aus ;;
  direkt) sperre; direkt ;;
  login) sperre; login ;;
  status) zeige_status ;;
  *)
    echo "Aufruf: vpn 1…9 | aus | direkt | login | status" >&2
    exit 2
    ;;
esac
