#!/usr/bin/env bash
# Fix Firewall - Restart firewall service to apply current DROP policies
set -euo pipefail

echo "Stopping VPN watchdog temporarily..."
sudo systemctl stop vpn-watchdog.timer vpn-watchdog.service

echo "Stopping WireGuard..."
sudo systemctl stop wg-quick-proton0.service

echo "Restarting firewall service (not reload!)..."
sudo systemctl restart firewall.service

echo "Waiting for firewall to be active..."
sleep 2

echo "Starting WireGuard..."
sudo systemctl start wg-quick-proton0.service

echo "Waiting for VPN to connect..."
sleep 3

echo "Starting VPN watchdog..."
sudo systemctl start vpn-watchdog.timer

echo ""
echo "✓ Done! Checking status..."
echo ""

sudo systemctl status wg-quick-proton0.service --no-pager -l | head -15
