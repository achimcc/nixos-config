#!/usr/bin/env bash
# Emergency Firewall Enable Script
# Reaktiviert Firewall, VPN und Security-Monitoring nach disable-firewall.sh
#
# Verwendung: sudo ./enable-firewall.sh

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
log_section "   FIREWALL & SECURITY REAKTIVIERUNG"
log_section "═══════════════════════════════════════════════════════"
echo ""

# ============================================================================
# Option 1: Vollständiger Rebuild (Empfohlen)
# ============================================================================
log_section "OPTION 1: Vollständiger Rebuild (Empfohlen)"
echo ""
log_info "Führt nixos-rebuild aus und stellt alle Konfigurationen wieder her:"
echo "   • Firewall-Regeln (VPN Kill Switch)"
echo "   • VPN-Verbindung (WireGuard ProtonVPN)"
echo "   • Intrusion Detection (Suricata IDS)"
echo "   • Security Monitoring (Logwatch, AIDE, etc.)"
echo "   • Alle systemd-Timer"
echo ""
read -p "Vollständigen Rebuild durchführen? (J/n): " -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Starte nixos-rebuild switch..."
    if nixos-rebuild switch --flake /home/achim/nixos-config#achim-laptop; then
        log_success "System erfolgreich neu konfiguriert!"

        # Kurz warten, dann Status prüfen
        sleep 3

        log_section "Status der kritischen Services:"
        systemctl is-active wg-quick-proton0 && log_success "VPN aktiv" || log_warning "VPN nicht aktiv"
        systemctl is-active suricata && log_success "Suricata IDS aktiv" || log_warning "Suricata nicht aktiv"
        systemctl is-active critical-alert-monitor.timer && log_success "Alert Monitor aktiv" || log_warning "Alert Monitor nicht aktiv"

        log_section "═══════════════════════════════════════════════════════"
        log_success "SICHERHEITSKONFIGURATION WIEDERHERGESTELLT"
        log_section "═══════════════════════════════════════════════════════"
        exit 0
    else
        log_error "Rebuild fehlgeschlagen!"
        log_info "Versuche manuelle Aktivierung (siehe unten)..."
    fi
fi

# ============================================================================
# Option 2: Manuelle Service-Aktivierung
# ============================================================================
log_section "OPTION 2: Manuelle Service-Aktivierung"
echo ""
log_warning "Nur verwenden, wenn Rebuild fehlgeschlagen ist!"
echo ""
read -p "Manuelle Aktivierung durchführen? (j/N): " -r
if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
    log_info "Abgebrochen. Starte System neu mit: sudo reboot"
    exit 0
fi

# ============================================================================
# 1. VPN-Verbindung starten
# ============================================================================
log_section "1️⃣  Starte VPN-Verbindung..."

if systemctl start wg-quick-proton0.service 2>&1; then
    log_success "WireGuard ProtonVPN gestartet"
    sleep 2

    # Prüfe VPN-Status
    if ip link show proton0 &>/dev/null; then
        VPN_IP=$(ip addr show proton0 | grep "inet " | awk '{print $2}')
        log_success "VPN-Interface aktiv: $VPN_IP"
    else
        log_error "VPN-Interface nicht gefunden!"
    fi
else
    log_error "Konnte VPN nicht starten!"
    log_info "Prüfe: journalctl -u wg-quick-proton0 -n 50"
fi

# ============================================================================
# 2. Firewall-Regeln laden (manuell)
# ============================================================================
log_section "2️⃣  Lade Firewall-Regeln..."

log_warning "NixOS Firewall wird durch nixos-rebuild aktiviert."
log_info "Für sofortige Aktivierung wird System-Rebuild empfohlen."

# ============================================================================
# 3. Security Services starten
# ============================================================================
log_section "3️⃣  Starte Security Services..."

services=(
    "suricata.service"
    "critical-alert-monitor.timer"
    "daily-security-report.timer"
    "aide-check.timer"
)

for service in "${services[@]}"; do
    if systemctl start "$service" 2>&1; then
        log_success "$service gestartet"
    else
        log_warning "Konnte $service nicht starten"
    fi
done

# Suricata Rule Update
if systemctl is-active --quiet suricata.service; then
    log_info "Starte Suricata Rule Update..."
    if systemctl start suricata-update.service 2>&1; then
        log_success "Suricata Regeln aktualisiert"
    else
        log_warning "Rule Update fehlgeschlagen (nicht kritisch)"
    fi
fi

# ============================================================================
# 4. Verbindungstest (über VPN)
# ============================================================================
log_section "4️⃣  Teste VPN-Verbindung..."

sleep 2

# Test 1: Ping über VPN
if timeout 5 ping -c 2 1.1.1.1 &>/dev/null; then
    log_success "ICMP-Ping über VPN funktioniert"
else
    log_error "ICMP-Ping fehlgeschlagen - VPN möglicherweise nicht aktiv!"
fi

# Test 2: Öffentliche IP prüfen
log_info "Prüfe öffentliche IP..."
PUBLIC_IP=$(timeout 5 curl -s https://api.ipify.org 2>/dev/null || echo "Timeout")
if [[ "$PUBLIC_IP" != "Timeout" ]]; then
    log_success "Öffentliche IP: $PUBLIC_IP"

    # Prüfe ob es eine ProtonVPN IP ist (heuristisch)
    if [[ "$PUBLIC_IP" =~ ^(185\.|146\.|156\.|149\.|193\.|91\.|89\.|37\.|79\.) ]]; then
        log_success "IP gehört wahrscheinlich zu ProtonVPN"
    else
        log_warning "IP gehört möglicherweise NICHT zu ProtonVPN!"
        log_warning "Prüfe VPN-Status: systemctl status wg-quick-proton0"
    fi
else
    log_error "Konnte öffentliche IP nicht abrufen - Netzwerk-Problem?"
fi

# ============================================================================
# 5. Firewall-Status prüfen
# ============================================================================
log_section "5️⃣  Prüfe Firewall-Status..."

# Prüfe ob nftables Service aktiv ist
NFTABLES_ACTIVE=false
if systemctl is-active --quiet nftables; then
    log_success "nftables Service aktiv"
    NFTABLES_ACTIVE=true
else
    log_warning "nftables Service nicht aktiv"
    log_warning "Führe nixos-rebuild aus, um Firewall zu aktivieren!"
fi

# Prüfe ob Drop-Regeln im Ruleset vorhanden sind
if [[ "$NFTABLES_ACTIVE" == true ]]; then
    RULESET=$(nft list ruleset 2>/dev/null)
    if echo "$RULESET" | grep -q "drop"; then
        log_success "Drop-Regeln im nftables Ruleset vorhanden"
    else
        log_warning "Keine Drop-Regeln gefunden - Firewall nicht vollständig konfiguriert"
    fi

    # Prüfe VPN-Interface-Regeln
    VPN_RULES=$(echo "$RULESET" | grep -c "proton0\|wg0\|proton-cli" || echo "0")
    if [[ "$VPN_RULES" -gt 0 ]]; then
        log_success "VPN-Regeln gefunden ($VPN_RULES Regeln)"
    else
        log_warning "Keine VPN-Regeln gefunden"
    fi
fi

# ============================================================================
# Status-Zusammenfassung
# ============================================================================
log_section "═══════════════════════════════════════════════════════"
log_section "   ZUSAMMENFASSUNG"
log_section "═══════════════════════════════════════════════════════"
echo ""

echo "Service-Status:"
systemctl is-active wg-quick-proton0 &>/dev/null && log_success "VPN: Aktiv" || log_error "VPN: Inaktiv"
systemctl is-active suricata &>/dev/null && log_success "IDS: Aktiv" || log_warning "IDS: Inaktiv"
systemctl is-active critical-alert-monitor.timer &>/dev/null && log_success "Alerts: Aktiv" || log_warning "Alerts: Inaktiv"

echo ""
if [[ "$NFTABLES_ACTIVE" == true ]]; then
    log_success "Firewall: Aktiv (Kill Switch aktiv)"
else
    log_error "Firewall: Inaktiv (Kill Switch NICHT aktiv!)"
fi

echo ""
log_section "═══════════════════════════════════════════════════════"

if [[ "$NFTABLES_ACTIVE" != true ]]; then
    echo ""
    log_error "ACHTUNG: Firewall ist nicht vollständig aktiv!"
    log_info "Führe aus: sudo nixos-rebuild switch --flake /home/achim/nixos-config#achim-laptop"
    echo ""
fi

log_info "Für vollständige Wiederherstellung empfohlen:"
echo "   ${GREEN}sudo reboot${NC}"
echo ""
