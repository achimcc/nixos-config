#!/usr/bin/env bash
# Script zum Deaktivieren der Firewall und Aufräumen von VPN-Interfaces
# Verwendung: sudo ./disable-firewall.sh

set -e

echo "🔧 Deaktiviere Firewall und räume VPN-Interfaces auf..."
echo ""

# 1. VPN-Interfaces runterfahren
echo "1️⃣  Fahre VPN-Interfaces herunter..."
ip link set proton0 down 2>/dev/null && echo "  ✓ proton0 down" || echo "  ℹ proton0 nicht vorhanden"
ip link set pvpnksintrf0 down 2>/dev/null && echo "  ✓ pvpnksintrf0 down" || echo "  ℹ pvpnksintrf0 nicht vorhanden"
ip link set tun0 down 2>/dev/null && echo "  ✓ tun0 down" || echo "  ℹ tun0 nicht vorhanden"
ip link set tun1 down 2>/dev/null && echo "  ✓ tun1 down" || echo "  ℹ tun1 nicht vorhanden"

# 2. ProtonVPN disconnecten
echo ""
echo "2️⃣  Trenne ProtonVPN-Verbindungen..."
protonvpn-cli d 2>/dev/null && echo "  ✓ ProtonVPN CLI disconnected" || echo "  ℹ ProtonVPN CLI nicht verbunden"
protonvpn-app --disconnect 2>/dev/null && echo "  ✓ ProtonVPN GUI disconnected" || echo "  ℹ ProtonVPN GUI nicht verbunden"

# 3. iptables flushen
echo ""
echo "3️⃣  Lösche iptables-Regeln..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
echo "  ✓ IPv4 iptables geflusht"

ip6tables -F
ip6tables -X
ip6tables -P INPUT ACCEPT
ip6tables -P OUTPUT ACCEPT
ip6tables -P FORWARD ACCEPT
echo "  ✓ IPv6 iptables geflusht"

# 4. Firewall-Service stoppen
echo ""
echo "4️⃣  Stoppe Firewall-Service..."
systemctl stop firewall.service 2>/dev/null && echo "  ✓ firewall.service gestoppt" || echo "  ℹ firewall.service nicht aktiv"
systemctl stop nftables.service 2>/dev/null && echo "  ✓ nftables.service gestoppt" || echo "  ℹ nftables.service nicht aktiv"

# 5. Default-Route wiederherstellen (falls nötig)
echo ""
echo "5️⃣  Prüfe Default-Route..."
if ! ip route show | grep -q "default via 192.168.178.1"; then
  echo "  ⚠ Keine Default-Route gefunden, füge hinzu..."
  ip route add default via 192.168.178.1 dev wlp0s20f3 2>/dev/null && echo "  ✓ Default-Route hinzugefügt" || echo "  ℹ Route existiert bereits"
else
  echo "  ✓ Default-Route vorhanden"
fi

# 6. NetworkManager neu starten (optional)
echo ""
echo "6️⃣  Starte NetworkManager neu (optional)..."
read -p "NetworkManager neu starten? (j/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[JjYy]$ ]]; then
  systemctl restart NetworkManager
  echo "  ⏳ Warte 5 Sekunden auf Netzwerk..."
  sleep 5
  echo "  ✓ NetworkManager neu gestartet"
else
  echo "  ℹ Übersprungen"
fi

# 7. Test
echo ""
echo "7️⃣  Teste Internetverbindung..."
if ping -c 2 1.1.1.1 &>/dev/null; then
  echo "  ✅ Internet funktioniert!"
else
  echo "  ❌ Kein Internet. Führe 'ip addr show' und 'ip route show' aus zum Debuggen."
fi

echo ""
echo "✅ Fertig! Firewall ist deaktiviert."
echo ""
echo "💡 Um die Firewall wieder zu aktivieren:"
echo "   sudo systemctl start firewall.service"
