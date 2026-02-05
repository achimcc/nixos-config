#!/usr/bin/env bash
# Test-Script: Überprüft ob das Netzwerk nach Boot funktioniert
# Dieses Script sollte OHNE disable-firewall.sh zu laufen funktionieren

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

echo "=== Network Boot Test ==="
echo ""

# Test 1: Check if firewall is active and rules are loaded
echo -n "Test 1: Firewall service active... "
if systemctl is-active --quiet firewall.service; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Firewall is not active!"
    FAILED=1
fi

echo -n "Test 1b: nftables rules loaded... "
if nft list table inet filter 2>/dev/null | grep -q "policy drop"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} nftables rules not loaded!"
    FAILED=1
fi

# Test 2: Check if NetworkManager is running
echo -n "Test 2: NetworkManager active... "
if systemctl is-active --quiet NetworkManager.service; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} NetworkManager is not active!"
    FAILED=1
fi

# Test 3: Check if WiFi interface has an IP
echo -n "Test 3: WiFi interface has IP... "
if ip addr show wlp0s20f3 | grep -q "inet "; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} No IP address on WiFi interface!"
    FAILED=1
fi

# Test 4: Check if default route exists
echo -n "Test 4: Default route exists... "
if ip route | grep -q "^default"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} No default route!"
    FAILED=1
fi

# Test 5: Check if we can ping gateway
echo -n "Test 5: Can ping gateway... "
if ping -c 1 -W 2 192.168.178.1 &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Cannot ping gateway!"
    FAILED=1
fi

# Test 6: Check if we can reach external IP
echo -n "Test 6: Can reach external IP... "
if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Cannot reach external IP!"
    FAILED=1
fi

# Test 7: Check if DNS works
echo -n "Test 7: DNS resolution works... "
if nslookup google.com &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} DNS resolution failed!"
    FAILED=1
fi

# Test 8: Check if HTTPS works
echo -n "Test 8: HTTPS connection works... "
if curl -s --max-time 5 https://www.google.com &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} HTTPS connection failed!"
    FAILED=1
fi

# Test 9: Check for ICMPv6 errors in NetworkManager logs
echo -n "Test 9: No ICMPv6 errors in logs... "
if journalctl -u NetworkManager -b --no-pager | grep -q "Operation not permitted"; then
    echo -e "${RED}✗${NC} Found 'Operation not permitted' errors!"
    FAILED=1
else
    echo -e "${GREEN}✓${NC}"
fi

# Test 10: Check for systemd ordering cycles
echo -n "Test 10: No systemd ordering cycles... "
if journalctl -b --no-pager | grep -q "ordering cycle"; then
    echo -e "${RED}✗${NC} Found systemd ordering cycle!"
    FAILED=1
else
    echo -e "${GREEN}✓${NC}"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== TESTS FAILED ===${NC}"
    exit 1
fi
