#!/usr/bin/env bash
# Emergency Firewall Enable Script
# Reaktiviert Firewall, VPN und Security-Monitoring nach disable-firewall.sh
#
# Verwendung: sudo ./enable-firewall.sh

set -euo pipefail

# Repo-Verzeichnis und Desktop-Nutzer zur Laufzeit ermitteln, statt sie fest
# einzutragen: Das Skript laeuft unter sudo (dann waere $HOME /root) und der
# Nutzername soll nicht im oeffentlichen Repo stehen.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_USER="$(id -nu 1000)"

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
echo "   • VPN-Verbindung (WireGuard-Slots via Befehl 'vpn')"
echo "   • Intrusion Detection (Suricata IDS)"
echo "   • Security Monitoring (Logwatch, AIDE, etc.)"
echo "   • Alle systemd-Timer"
echo ""
read -p "Vollständigen Rebuild durchführen? (J/n): " -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Starte nixos-rebuild switch..."
    if nixos-rebuild switch --flake $REPO_DIR#nixos; then
        log_success "System erfolgreich neu konfiguriert!"

        # Kurz warten, dann Status prüfen
        sleep 3

        log_section "Status der kritischen Services:"
        # Zustand kommt aus /run/vpn/status.json (geschrieben von modules/vpn.nix), nicht
        # aus einem festen Interface-Namen.
        if [ -r /run/vpn/status.json ] && jq -e '.slot != null' /run/vpn/status.json &>/dev/null; then
            VPN_SLOT=$(jq -r '.slot' /run/vpn/status.json)
            log_success "VPN aktiv (Slot $VPN_SLOT)"
        else
            log_warning "VPN nicht verbunden (als Nutzer: vpn login)"
        fi
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
# 1. WireGuard-Slot verbinden
# ============================================================================
log_section "1️⃣  Verbinde VPN (letzter Slot)..."

# 'vpn login' verbindet den zuletzt benutzten Slot (siehe modules/vpn/vpn.sh).
# Fehlschlag ist hier nicht fatal: Der Nutzer kann den Slot manuell wählen (vpn 1…9).
if sudo -u "$DESKTOP_USER" XDG_RUNTIME_DIR=/run/user/1000 /run/current-system/sw/bin/vpn login 2>&1; then
    log_success "vpn login ausgeführt"
    sleep 3

    if [ -r /run/vpn/status.json ] && jq -e '.slot != null' /run/vpn/status.json &>/dev/null; then
        VPN_SLOT=$(jq -r '.slot' /run/vpn/status.json)
        log_success "VPN-Slot aktiv: $VPN_SLOT"
    else
        log_warning "VPN noch nicht verbunden - Status prüfen mit: vpn status"
    fi
else
    log_warning "vpn login fehlgeschlagen - Slot manuell wählen: vpn 1…9"
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
    log_info "Ob es die Exit-IP des verbundenen Slots ist, prüft 'vpn status' gegen den Exit-IP-Dienst."
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
    VPN_RULES=$(echo "$RULESET" | grep -c 'wg\*' || echo "0")
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
if [ -r /run/vpn/status.json ] && jq -e '.slot != null' /run/vpn/status.json &>/dev/null; then
    VPN_SLOT=$(jq -r '.slot' /run/vpn/status.json)
    log_success "VPN: Aktiv (Slot $VPN_SLOT)"
else
    log_warning "VPN: Nicht verbunden (vpn login oder vpn 1…9)"
fi
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
    log_info "Führe aus: sudo nixos-rebuild switch --flake $REPO_DIR#nixos"
    echo ""
fi

log_info "Für vollständige Wiederherstellung empfohlen:"
echo "   ${GREEN}sudo reboot${NC}"
echo ""
