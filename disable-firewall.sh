#!/usr/bin/env bash
# Emergency Firewall Disable Script
# Deaktiviert alle Firewall-Regeln, VPN und Security-Monitoring
#
# WARNUNG: Dies deaktiviert den VPN Kill Switch!
# Internet-Traffic wird OHNE VPN geleakt!
#
# Verwendung: sudo ./disable-firewall.sh

set -euo pipefail

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}ℹ${NC}  $*"; }
log_success() { echo -e "${GREEN}✓${NC}  $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC}  $*"; }
log_error() { echo -e "${RED}✗${NC}  $*"; }
log_section() { echo -e "\n${BLUE}$*${NC}"; }

# Root check
if [[ $EUID -ne 0 ]]; then
   log_error "Dieses Script muss als root ausgeführt werden (sudo)"
   exit 1
fi

log_section "═══════════════════════════════════════════════════════"
log_section "   EMERGENCY FIREWALL DISABLE"
log_section "═══════════════════════════════════════════════════════"
echo ""
log_warning "WARNUNG: VPN Kill Switch wird deaktiviert!"
log_warning "Internet-Traffic wird OHNE VPN-Verschlüsselung gesendet!"
echo ""
read -p "Fortfahren? (yes/NO): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Abgebrochen."
    exit 0
fi

# ============================================================================
# 1. Security Monitoring Services stoppen
# ============================================================================
log_section "1️⃣  Stoppe Security Monitoring Services..."

services=(
    "suricata.service"
    "critical-alert-monitor.timer"
    "daily-security-report.timer"
    "aide-check.timer"
    "unhide-check.timer"
    "unhide-tcp-check.timer"
    "chkrootkit-check.timer"
)

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" && log_success "$service gestoppt" || log_warning "Konnte $service nicht stoppen"
    else
        log_info "$service war nicht aktiv"
    fi
done

# ============================================================================
# 2. VPN-Verbindungen trennen
# ============================================================================
log_section "2️⃣  Trenne VPN-Verbindungen..."

# WireGuard ProtonVPN
if systemctl is-active --quiet wg-quick-proton0.service 2>/dev/null; then
    systemctl stop wg-quick-proton0.service && log_success "WireGuard ProtonVPN gestoppt"
else
    log_info "WireGuard Service nicht aktiv"
fi

# Manuelle WireGuard Interfaces
for iface in proton0 wg0 wg1; do
    if ip link show "$iface" &>/dev/null; then
        wg-quick down "$iface" 2>/dev/null && log_success "$iface down" || log_info "$iface bereits down"
    fi
done

# OpenVPN Interfaces
for iface in tun0 tun1 pvpnksintrf0; do
    if ip link show "$iface" &>/dev/null; then
        ip link set "$iface" down 2>/dev/null && log_success "$iface down" || log_info "$iface bereits down"
    fi
done

# ============================================================================
# 3. Firewall-Regeln zurücksetzen
# ============================================================================
log_section "3️⃣  Setze Firewall-Regeln zurück..."

# IPv4 iptables
log_info "Resette IPv4 iptables..."
iptables -F INPUT 2>/dev/null || true
iptables -F OUTPUT 2>/dev/null || true
iptables -F FORWARD 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
iptables -t raw -F 2>/dev/null || true
iptables -t raw -X 2>/dev/null || true
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
log_success "IPv4 Firewall deaktiviert"

# IPv6 ip6tables
log_info "Resette IPv6 ip6tables..."
ip6tables -F INPUT 2>/dev/null || true
ip6tables -F OUTPUT 2>/dev/null || true
ip6tables -F FORWARD 2>/dev/null || true
ip6tables -X 2>/dev/null || true
ip6tables -t nat -F 2>/dev/null || true
ip6tables -t nat -X 2>/dev/null || true
ip6tables -t mangle -F 2>/dev/null || true
ip6tables -t mangle -X 2>/dev/null || true
ip6tables -P INPUT ACCEPT
ip6tables -P OUTPUT ACCEPT
ip6tables -P FORWARD ACCEPT
log_success "IPv6 Firewall deaktiviert"

# ============================================================================
# 4. Policy-Routing-Regeln bereinigen
# ============================================================================
log_section "4️⃣  Bereinige Policy-Routing-Regeln..."

# Liste alle Policy-Routing-Regeln auf
log_info "Aktuelle Policy-Routing-Regeln:"
ip rule show | grep -v "^0:" | grep -v "^32766:" | grep -v "^32767:" || log_info "Keine benutzerdefinierten Regeln gefunden"

# Entferne alle Regeln, die auf VPN-Tabellen (z.B. 51820) verweisen
log_info "Entferne VPN-Policy-Routing-Regeln..."
removed_count=0
while ip rule show | grep -q "lookup 51820"; do
    ip rule del table 51820 2>/dev/null && ((removed_count++)) || break
done

if [ $removed_count -gt 0 ]; then
    log_success "$removed_count VPN-Policy-Routing-Regel(n) entfernt"
else
    log_info "Keine VPN-Policy-Routing-Regeln gefunden"
fi

# Entferne alle fwmark-basierten Regeln
log_info "Entferne fwmark-basierte Routing-Regeln..."
removed_fwmark=0
while ip rule show | grep -q "fwmark"; do
    # Extrahiere die Priority der Regel und lösche sie
    PRIORITY=$(ip rule show | grep "fwmark" | head -1 | grep -oP 'lookup \d+' | awk '{print $2}')
    if [ -n "$PRIORITY" ]; then
        ip rule del table "$PRIORITY" 2>/dev/null && ((removed_fwmark++)) || break
    else
        break
    fi
done

if [ $removed_fwmark -gt 0 ]; then
    log_success "$removed_fwmark fwmark-Regel(n) entfernt"
else
    log_info "Keine fwmark-basierten Regeln gefunden"
fi

# Stelle sicher, dass Standard-Routing-Regeln vorhanden sind
log_info "Prüfe Standard-Routing-Regeln..."
if ! ip rule show | grep -q "^0:"; then
    ip rule add priority 0 from all lookup local 2>/dev/null || true
fi
if ! ip rule show | grep -q "^32766:"; then
    ip rule add priority 32766 from all lookup main 2>/dev/null || true
fi
if ! ip rule show | grep -q "^32767:"; then
    ip rule add priority 32767 from all lookup default 2>/dev/null || true
fi
log_success "Standard-Routing-Regeln überprüft"

# ============================================================================
# 5. Netzwerk-Routing prüfen
# ============================================================================
log_section "5️⃣  Prüfe Netzwerk-Routing..."

# Dynamisch WiFi-Interface erkennen
WIFI_IFACE=$(ip link show | grep -E "^\s*[0-9]+:\s*(wlp|wlan)" | head -1 | cut -d: -f2 | tr -d ' ')
if [[ -z "$WIFI_IFACE" ]]; then
    log_warning "Kein WiFi-Interface gefunden, versuche Ethernet..."
    WIFI_IFACE=$(ip link show | grep -E "^\s*[0-9]+:\s*(enp|eth)" | head -1 | cut -d: -f2 | tr -d ' ')
fi

if [[ -n "$WIFI_IFACE" ]]; then
    log_success "Netzwerk-Interface: $WIFI_IFACE"

    # Prüfe Default-Route
    if ! ip route show | grep -q "^default"; then
        log_warning "Keine Default-Route gefunden, versuche hinzuzufügen..."

        # Versuche Router-IP zu finden
        ROUTER_IP=$(ip route show | grep "^192.168.178" | grep -oP '(?<=via )\S+' | head -1)
        if [[ -z "$ROUTER_IP" ]]; then
            ROUTER_IP="192.168.178.1"  # Fallback
        fi

        ip route add default via "$ROUTER_IP" dev "$WIFI_IFACE" 2>/dev/null && \
            log_success "Default-Route hinzugefügt: via $ROUTER_IP dev $WIFI_IFACE" || \
            log_info "Route existiert bereits oder konnte nicht hinzugefügt werden"
    else
        log_success "Default-Route vorhanden"
    fi
else
    log_error "Kein Netzwerk-Interface gefunden!"
fi

# ============================================================================
# 6. NetworkManager neu starten (optional)
# ============================================================================
log_section "6️⃣  NetworkManager neu starten?"

read -p "NetworkManager neu starten? (j/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[JjYy]$ ]]; then
    systemctl restart NetworkManager
    log_info "Warte 5 Sekunden auf Netzwerk..."
    sleep 5
    log_success "NetworkManager neu gestartet"
else
    log_info "Übersprungen"
fi

# ============================================================================
# 7. DNS-Konfiguration prüfen
# ============================================================================
log_section "7️⃣  Prüfe DNS-Konfiguration..."

if systemctl is-active --quiet systemd-resolved; then
    log_success "systemd-resolved läuft"
    resolvectl status | grep -A5 "Global" | grep "DNS Servers" || log_warning "Keine DNS-Server konfiguriert"
else
    log_warning "systemd-resolved ist nicht aktiv"
fi

# ============================================================================
# 8. Verbindungstest
# ============================================================================
log_section "8️⃣  Teste Internetverbindung..."

# Test 1: Ping
if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    log_success "ICMP-Ping funktioniert (1.1.1.1)"
else
    log_warning "ICMP-Ping fehlgeschlagen"
fi

# Test 2: DNS
if nslookup google.com &>/dev/null; then
    log_success "DNS-Auflösung funktioniert"
else
    log_warning "DNS-Auflösung fehlgeschlagen"
fi

# Test 3: HTTP
if curl -s --max-time 5 https://www.google.com &>/dev/null; then
    log_success "HTTPS-Verbindung funktioniert"
else
    log_warning "HTTPS-Verbindung fehlgeschlagen"
fi

# ============================================================================
# Status-Zusammenfassung
# ============================================================================
log_section "═══════════════════════════════════════════════════════"
log_section "   STATUS"
log_section "═══════════════════════════════════════════════════════"
echo ""

log_warning "⚠  FIREWALL IST DEAKTIVIERT"
log_warning "⚠  VPN KILL SWITCH IST DEAKTIVIERT"
log_warning "⚠  INTRUSION DETECTION IST GESTOPPT"
log_warning "⚠  INTERNET-TRAFFIC IST NICHT VERSCHLÜSSELT"
echo ""

# Aktuelle IP anzeigen
log_info "Deine aktuelle öffentliche IP:"
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Konnte IP nicht abrufen")
echo "   $PUBLIC_IP"
echo ""

log_section "═══════════════════════════════════════════════════════"
log_section "   WIEDERHERSTELLUNG"
log_section "═══════════════════════════════════════════════════════"
echo ""
log_info "Um die Sicherheitskonfiguration wiederherzustellen:"
echo ""
echo "   1. Firewall reaktivieren:"
echo "      ${GREEN}sudo nixos-rebuild switch --flake /home/achim/nixos-config#achim-laptop${NC}"
echo ""
echo "   2. Oder nur Services neu starten:"
echo "      ${GREEN}sudo systemctl start wg-quick-proton0${NC}"
echo "      ${GREEN}sudo systemctl start suricata${NC}"
echo ""
echo "   3. System neu starten (empfohlen):"
echo "      ${GREEN}sudo reboot${NC}"
echo ""
