#!/usr/bin/env bash
# Restore VPN and Kill Switch - Fixed configuration
set -euo pipefail

# Repo-Verzeichnis und Desktop-Nutzer zur Laufzeit ermitteln, statt sie fest
# einzutragen: Das Skript laeuft unter sudo (dann waere $HOME /root) und der
# Nutzername soll nicht im oeffentlichen Repo stehen.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_USER="$(id -nu 1000)"

echo "════════════════════════════════════════════════════════"
echo "  RESTORE VPN KILL SWITCH"
echo "════════════════════════════════════════════════════════"
echo ""
echo "This will:"
echo "  1. Rebuild system with fixed VPN dependencies"
echo "  2. Restore firewall DROP policies (kill switch)"
echo "  3. Start VPN with persistent connection"
echo ""
read -p "Continue? (yes/NO): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "→ Configuring git safe directory for root..."
sudo git config --global --add safe.directory $REPO_DIR 2>/dev/null || true

echo ""
echo "→ Building system configuration..."
sudo nixos-rebuild switch --flake $REPO_DIR#nixos

echo ""
echo "→ Restarting firewall service (to apply DROP policies)..."
sudo systemctl restart firewall.service

echo ""
echo "→ Waiting for firewall to be active..."
sleep 2

echo ""
echo "→ Starting VPN..."
sudo systemctl restart wg-quick-proton0.service

echo ""
echo "→ Waiting for VPN connection..."
sleep 5

echo ""
echo "→ Checking VPN status..."
sudo systemctl status wg-quick-proton0.service --no-pager -l | head -15

echo ""
echo "→ Testing VPN interface..."
if ip link show proton0 &>/dev/null; then
    echo "✓ VPN interface exists"
    ip addr show proton0 | grep "inet "
else
    echo "✗ VPN interface not found"
    exit 1
fi

echo ""
echo "→ Testing internet connectivity through VPN..."
if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    echo "✓ Internet working through VPN"
else
    echo "✗ No internet (kill switch may be blocking - check firewall)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✓ VPN KILL SWITCH RESTORED"
echo "════════════════════════════════════════════════════════"
echo ""
echo "The VPN should now stay connected even when the firewall"
echo "is reloaded during system updates."
echo ""
