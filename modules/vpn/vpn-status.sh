# vpn-status — misst alle 2 s den VPN-Zustand und schreibt /run/vpn/status.json.
# Läuft als root: wg und nft brauchen CAP_NET_ADMIN. Leser: Leiste und `vpn status`.
#
# Gemessen wird am Kernel (wg, nft), nicht an NetworkManager: Ein aktives Profil
# ohne Handshake soll als solches sichtbar sein, nicht als "verbunden".
# Achtung pipefail: `… | grep -q` kann den Schreiber per SIGPIPE beenden und die
# Pipeline dann als Fehlschlag melden. Deshalb erst in Variablen lesen.

server_json=/etc/vpn/server.json
ziel=/run/vpn/status.json

while true; do
  jetzt=$(date +%s)
  slot=null
  name=null
  alter=null
  rx=null
  tx=null

  iface=$(wg show interfaces | tr ' ' '\n' | grep -E '^wg-[1-9]$' | head -n 1 || true)
  if [ -n "$iface" ]; then
    slot=${iface#wg-}
    name=$(jq -c --argjson s "$slot" '[.[] | select(.slot == $s) | .name][0]' "$server_json")

    hs=$(wg show "$iface" latest-handshakes | awk 'NR == 1 { print $2 }')
    if [ -n "$hs" ] && [ "$hs" -gt 0 ]; then
      alter=$((jetzt - hs))
    fi

    transfer=$(wg show "$iface" transfer | awk 'NR == 1 { print $2, $3 }')
    if [ -n "$transfer" ]; then
      rx=${transfer% *}
      tx=${transfer#* }
    fi
  fi

  # Wahrheit für "Direkt" ist die Chain, nicht der Unit-Zustand: ein nftables-Reload
  # leert die Chain, die Unit bliebe "active".
  kette_direkt=$(nft list chain inet filter direkt 2>/dev/null || true)
  direkt=false
  if grep -qw accept <<<"$kette_direkt"; then
    direkt=true
  fi

  kette_output=$(nft list chain inet filter output 2>/dev/null || true)
  killswitch=false
  if grep -q 'policy drop' <<<"$kette_output"; then
    killswitch=true
  fi

  jq -n \
    --argjson zeit "$jetzt" --argjson slot "$slot" --argjson name "$name" \
    --argjson handshake_alter "$alter" --argjson rx "$rx" --argjson tx "$tx" \
    --argjson direkt "$direkt" --argjson killswitch "$killswitch" \
    '{zeit: $zeit, slot: $slot, name: $name, handshake_alter: $handshake_alter,
      rx: $rx, tx: $tx, direkt: $direkt, killswitch: $killswitch}' \
    > "$ziel.tmp"
  mv "$ziel.tmp" "$ziel"

  sleep 2
done
