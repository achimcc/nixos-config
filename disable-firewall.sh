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

# WireGuard ProtonVPN (CLI + GUI)
for vpn_svc in wg-quick-proton-cli.service wg-quick-proton0.service; do
    if systemctl is-active --quiet "$vpn_svc" 2>/dev/null; then
        systemctl stop "$vpn_svc" && log_success "$vpn_svc gestoppt"
    else
        log_info "$vpn_svc nicht aktiv"
    fi
done

# Manuelle WireGuard Interfaces
for iface in proton-cli proton0 wg0 wg1; do
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

# nftables Service stoppen (nicht nur flush - verhindert dass systemd ihn neu startet)
log_info "Stoppe nftables Service..."
systemctl stop nftables 2>/dev/null && log_success "nftables Service gestoppt" || log_info "nftables Service war nicht aktiv"
nft flush ruleset 2>/dev/null || true
log_success "nftables Firewall deaktiviert"

# Legacy iptables cleanup (in case old rules exist)
log_info "Bereinige eventuelle legacy iptables-Regeln..."
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
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true

ip6tables -F INPUT 2>/dev/null || true
ip6tables -F OUTPUT 2>/dev/null || true
ip6tables -F FORWARD 2>/dev/null || true
ip6tables -X 2>/dev/null || true
ip6tables -t nat -F 2>/dev/null || true
ip6tables -t nat -X 2>/dev/null || true
ip6tables -t mangle -F 2>/dev/null || true
ip6tables -t mangle -X 2>/dev/null || true
ip6tables -P INPUT ACCEPT 2>/dev/null || true
ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
ip6tables -P FORWARD ACCEPT 2>/dev/null || true
log_success "Legacy iptables bereinigt"

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
# 5. ProtonVPN-Cleanup & WiFi-Verbindung reparieren
# ============================================================================
log_section "5️⃣  WiFi-Verbindung reparieren..."

# 5a. ProtonVPN GUI-Verbindungen löschen (übernehmen DNS/Routing auf WiFi)
log_info "Entferne ProtonVPN NM-Verbindungen..."
PVPN_REMOVED=0
for f in /etc/NetworkManager/system-connections/pvpn-killswitch* /etc/NetworkManager/system-connections/ProtonVPN*; do
    if [ -f "$f" ]; then
        rm -f "$f"
        log_success "Gelöscht: $(basename "$f")"
        ((PVPN_REMOVED++))
    fi
done
if [ $PVPN_REMOVED -eq 0 ]; then
    log_info "Keine ProtonVPN-Verbindungen gefunden"
else
    log_success "$PVPN_REMOVED ProtonVPN-Verbindung(en) gelöscht"
    # NM muss die gelöschten Dateien bemerken
    nmcli connection reload 2>/dev/null || true
fi

# 5b. WiFi-Passwort aus sops lesen
WIFI_PSK=""
if [ -f /run/secrets/wifi/home ]; then
    WIFI_PSK=$(cat /run/secrets/wifi/home)
    log_success "WiFi-Passwort aus sops gelesen"
else
    log_warning "sops Secret /run/secrets/wifi/home nicht gefunden"
    log_info "WiFi-Verbindung nur möglich wenn Greenside4-Profil existiert"
fi

# 5c. WiFi-Interface erkennen
WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep ":wifi" | cut -d: -f1 | head -1)
if [[ -z "$WIFI_IFACE" ]]; then
    log_warning "Kein WiFi-Interface gefunden, versuche Ethernet..."
    WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep ":ethernet" | cut -d: -f1 | head -1)
fi

if [[ -n "$WIFI_IFACE" ]]; then
    log_success "Netzwerk-Interface: $WIFI_IFACE"

    # Finde aktive Verbindung auf dem Interface
    WIFI_CON=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":${WIFI_IFACE}$" | cut -d: -f1)

    if [[ -n "$WIFI_CON" ]]; then
        log_info "Aktive Verbindung: $WIFI_CON"

        # Prüfe ob IPv4-Adresse vorhanden
        if ip addr show "$WIFI_IFACE" | grep -q "inet "; then
            CURRENT_IP=$(ip addr show "$WIFI_IFACE" | grep "inet " | awk '{print $2}')
            log_success "IPv4-Adresse vorhanden: $CURRENT_IP"
        else
            # Keine IPv4 → Verbindung reaktivieren
            log_warning "Keine IPv4-Adresse auf $WIFI_IFACE"
            log_info "Reaktiviere Verbindung '$WIFI_CON' (down + up)..."
            nmcli connection down "$WIFI_CON" 2>/dev/null || true
            sleep 2
            nmcli connection up "$WIFI_CON" 2>/dev/null && \
                log_success "Verbindung '$WIFI_CON' reaktiviert" || \
                log_warning "Konnte Verbindung nicht reaktivieren"
        fi
    else
        # Keine aktive Verbindung → Greenside4 verbinden
        log_warning "Keine aktive Verbindung auf $WIFI_IFACE"

        if [[ -n "$WIFI_PSK" ]]; then
            # Passwort aus sops verfügbar → automatisch verbinden
            log_info "Verbinde mit Greenside4 (Passwort aus sops)..."
            nmcli device wifi connect Greenside4 password "$WIFI_PSK" 2>/dev/null && \
                log_success "Mit Greenside4 verbunden" || \
                log_warning "Konnte nicht mit Greenside4 verbinden"
        elif nmcli connection show "Greenside4" &>/dev/null; then
            # Profil existiert → versuche ohne Passwort
            log_info "Versuche Greenside4-Profil zu aktivieren..."
            nmcli connection up "Greenside4" 2>/dev/null && \
                log_success "Mit Greenside4 verbunden" || \
                log_warning "Konnte nicht mit Greenside4 verbinden"
        else
            log_warning "Kein WiFi-Passwort und kein Greenside4-Profil verfügbar"
            log_info "Manuelle Verbindung nötig: nmcli --ask device wifi connect Greenside4"
        fi
    fi

    # Warte auf DHCP IPv4-Adresse (max 15 Sekunden)
    if ! ip addr show "$WIFI_IFACE" | grep -q "inet "; then
        log_info "Warte auf DHCP IPv4-Zuweisung..."
        for i in $(seq 1 15); do
            if ip addr show "$WIFI_IFACE" | grep -q "inet "; then
                CURRENT_IP=$(ip addr show "$WIFI_IFACE" | grep "inet " | awk '{print $2}')
                log_success "IPv4-Adresse erhalten: $CURRENT_IP (nach ${i}s)"
                break
            fi
            sleep 1
        done

        # Fallback: Manuelle IP wenn DHCP nicht funktioniert hat
        if ! ip addr show "$WIFI_IFACE" | grep -q "inet "; then
            log_warning "Kein DHCP nach 15s, setze manuelle IP..."
            ip addr add 192.168.178.100/24 dev "$WIFI_IFACE" 2>/dev/null && \
                log_success "Manuelle IP 192.168.178.100/24 gesetzt" || \
                log_warning "Konnte manuelle IP nicht setzen"
        fi
    fi

    # Default-Route prüfen
    if ! ip route show | grep -q "^default"; then
        log_warning "Keine Default-Route gefunden, versuche hinzuzufügen..."

        # Router-IP aus bestehendem Subnetz ermitteln
        ROUTER_IP=$(ip route show | grep -oP '^\d+\.\d+\.\d+' | head -1)
        if [[ -n "$ROUTER_IP" ]]; then
            ROUTER_IP="${ROUTER_IP}.1"
        else
            ROUTER_IP="192.168.178.1"  # Fallback Fritz!Box
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
echo "      ${GREEN}sudo nixos-rebuild switch --flake /home/achim/nixos-config#nixos${NC}"
echo ""
echo "   2. Oder nur Services neu starten:"
echo "      ${GREEN}sudo systemctl start nftables${NC}"
echo "      ${GREEN}sudo systemctl start wg-quick-proton-cli${NC}"
echo "      ${GREEN}sudo systemctl start suricata${NC}"
echo ""
echo "   3. System neu starten (empfohlen):"
echo "      ${GREEN}sudo reboot${NC}"
echo ""
