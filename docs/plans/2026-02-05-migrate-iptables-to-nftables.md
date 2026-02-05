# Firewall Migration: iptables to nftables Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate firewall configuration from iptables to nftables while maintaining identical security behavior

**Architecture:** Replace iptables commands in firewall.nix with equivalent nftables rules using NixOS networking.nftables module. Update disable-firewall.sh to use nft commands. Ensure DNS-over-TLS bootstrap strategy, VPN kill switch, and all security policies remain intact.

**Tech Stack:** NixOS networking.nftables, nft commands, systemd service ordering

---

## Background

The current firewall uses iptables/ip6tables with complex rules for:
- VPN kill switch (blocks all traffic except through VPN interfaces)
- DNS-over-TLS dual-phase strategy (Quad9 bootstrap, Mullvad over VPN)
- DHCP/DNS/mDNS local network services
- Syncthing, printer access
- Port scan detection and logging
- ICMPv6 Neighbor Discovery for NetworkManager

**Critical Requirements:**
1. Network MUST function at boot (DNS bootstrap deadlock was previously resolved)
2. Firewall starts BEFORE NetworkManager (VPN kill switch requirement)
3. All firewall rules must be 1:1 translated to nftables
4. test-network-boot.sh must pass after migration

---

## Task 1: Create nftables firewall configuration

**Files:**
- Modify: `modules/firewall.nix:85-293`

**Step 1: Replace networking.firewall with networking.nftables**

Remove the entire `networking.firewall` block and replace with nftables configuration.

```nix
networking.nftables = {
  enable = true;

  ruleset = ''
    # Flush existing ruleset
    flush ruleset

    # ==========================================
    # IPv4 FIREWALL TABLE
    # ==========================================
    table inet filter {
      # Port scan detection set
      set portscan {
        type ipv4_addr
        flags dynamic, timeout
        timeout 60s
      }

      # INPUT CHAIN
      chain input {
        type filter hook input priority filter; policy drop;

        # 1. Loopback traffic
        iif lo accept

        # 2. Established/Related connections
        ct state established,related accept

        # 3. DHCP responses (server:67 -> client:68)
        udp sport 67 udp dport 68 accept

        # 4. mDNS for local discovery (Avahi)
        udp dport 5353 ip saddr 224.0.0.251 accept

        # 5. Printer (Brother MFC-7360N) - IPP/CUPS and Raw Printing
        ip saddr ${localNetwork.printerIP} tcp sport 631 accept

        # 6. Syncthing - Local network
        ip saddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
        ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
        ip saddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept

        # 7. Syncthing - Over VPN interfaces
        iifname "proton0" tcp dport ${toString syncthingPorts.tcp} accept
        iifname "tun*" tcp dport ${toString syncthingPorts.tcp} accept
        iifname "wg*" tcp dport ${toString syncthingPorts.tcp} accept
        iifname "proton0" udp dport ${toString syncthingPorts.quic} accept
        iifname "tun*" udp dport ${toString syncthingPorts.quic} accept
        iifname "wg*" udp dport ${toString syncthingPorts.quic} accept

        # 8. Port-scan detection
        update @portscan { ip saddr limit rate over 10/minute } drop

        # 9. Logging dropped packets (rate limited)
        limit rate 1/minute burst 3 packets log prefix "FW-DROP-IN: " level info
      }

      # OUTPUT CHAIN
      chain output {
        type filter hook output priority filter; policy drop;

        # 1. Loopback traffic
        oif lo accept

        # 2. Established/Related connections
        ct state established,related accept

        # 3. VPN interfaces - allow ALL traffic
        oifname "proton0" accept
        oifname "tun*" accept
        oifname "wg*" accept

        # 4. VPN connection establishment (physical interface)
        udp dport ${toString vpnPorts.wireguard} accept
        udp dport ${toString vpnPorts.wireguardAlt1} accept
        udp dport ${toString vpnPorts.wireguardAlt2} accept
        udp dport ${toString vpnPorts.openvpn} accept
        tcp dport ${toString vpnPorts.https} accept
        udp dport ${toString vpnPorts.https} accept
        udp dport ${toString vpnPorts.ikev2} accept
        udp dport ${toString vpnPorts.ikev2Nat} accept

        # 5. DHCP requests (client:68 -> broadcast:67)
        udp sport 68 udp dport 67 accept

        # 6. DNS to systemd-resolved stub only
        ip daddr ${dnsServers.stubListener} udp dport 53 accept
        ip daddr ${dnsServers.stubListener} tcp dport 53 accept

        # 7. DNS-over-TLS - Bootstrap phase (Quad9)
        ip daddr 9.9.9.9 tcp dport 853 accept

        # 8. DNS-over-TLS - VPN phase (Mullvad)
        oifname "proton0" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
        oifname "tun*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept
        oifname "wg*" ip daddr ${dnsServers.mullvad} tcp dport 853 accept

        # 9. Block all other DNS-over-TLS (prevent leaks)
        tcp dport 853 drop
        udp dport 853 drop

        # 10. mDNS for local discovery
        ip daddr 224.0.0.251 udp dport 5353 accept

        # 11. Printer access
        ip daddr ${localNetwork.printerIP} tcp dport 631 accept
        ip daddr ${localNetwork.printerIP} tcp dport 9100 accept

        # 12. Syncthing - Local network only
        ip daddr ${localNetwork.subnet} tcp dport ${toString syncthingPorts.tcp} accept
        ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.quic} accept
        ip daddr ${localNetwork.subnet} udp dport ${toString syncthingPorts.discovery} accept

        # 13. Syncthing broadcast discovery
        ip daddr 255.255.255.255 udp dport ${toString syncthingPorts.discovery} accept
        ip daddr 192.168.178.255 udp dport ${toString syncthingPorts.discovery} accept

        # 14. Logging dropped packets (rate limited)
        limit rate 1/minute burst 3 packets log prefix "FW-DROP-OUT: " level info
      }

      # FORWARD CHAIN
      chain forward {
        type filter hook forward priority filter; policy drop;

        # Log and block all forwarding (this machine is not a router)
        limit rate 1/minute burst 3 packets log prefix "FW-FORWARD-BLOCKED: " level info
      }
    }

    # ==========================================
    # IPv6 FIREWALL TABLE
    # ==========================================
    table ip6 filter {
      # INPUT CHAIN
      chain input {
        type filter hook input priority filter; policy drop;

        # 1. Loopback traffic
        iif lo accept

        # 2. Established/Related connections
        ct state established,related accept

        # 3. ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
        icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

        # 4. Logging dropped packets
        limit rate 1/minute log prefix "ip6-blocked-in: " level info
      }

      # OUTPUT CHAIN
      chain output {
        type filter hook output priority filter; policy drop;

        # 1. Loopback traffic
        oif lo accept

        # 2. Established/Related connections
        ct state established,related accept

        # 3. ICMPv6 Neighbor Discovery (CRITICAL for NetworkManager)
        icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept

        # 4. Logging dropped packets
        limit rate 1/minute log prefix "ip6-blocked-out: " level info
      }

      # FORWARD CHAIN
      chain forward {
        type filter hook forward priority filter; policy drop;
      }
    }
  '';
};
```

**Step 2: Remove old iptables checkReversePath setting**

Remove this line (no longer needed with nftables):
```nix
checkReversePath = false;
```

**Step 3: Verify the configuration compiles**

Run: `nix build .#nixosConfigurations.achim-laptop.config.system.build.toplevel --show-trace`
Expected: Build succeeds without errors

**Step 4: Update comments at top of file**

Change lines 6-8 from:
```nix
# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit iptables
# Migration zu nftables mit nativen Zonen in Zukunft geplant
```

To:
```nix
# HINWEIS: Netzwerk-Zonen-Konzept dokumentiert in firewall-zones.nix
# Diese Datei implementiert die Zonen-Regeln mit nftables
# Migriert von iptables zu nftables am 2026-02-05
```

**Step 5: Commit**

```bash
git add modules/firewall.nix
git commit -m "feat: migrate firewall from iptables to nftables

- Replace networking.firewall with networking.nftables
- Translate all iptables rules to nftables syntax 1:1
- Maintain VPN kill switch, DNS-over-TLS bootstrap, port scan detection
- Preserve ICMPv6 Neighbor Discovery for NetworkManager
- All security policies remain identical

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Update protonvpn.nix firewall validation

**Files:**
- Modify: `modules/protonvpn.nix:66`

**Step 1: Update firewall validation script**

The VPN pre-check script validates that firewall rules are loaded by checking for "DROP" policy in iptables output. This needs to check nftables instead.

Replace lines 61-78:
```nix
ExecStartPre = pkgs.writeShellScript "vpn-pre-check" ''
  # Wait for firewall to be active (max 30s)
  for i in $(seq 1 30); do
    if systemctl is-active --quiet firewall.service; then
      # Verify firewall rules are loaded (DROP policy active)
      if ${pkgs.iptables}/bin/iptables -L OUTPUT -n | grep -q "DROP"; then
        echo "✓ Firewall active with DROP policy - safe to start VPN"
        exit 0
      fi
    fi
    sleep 1
  done

  # WARNING: Proceed anyway to avoid boot lockup
  # The VPN watchdog will monitor and alert if firewall fails later
  echo "⚠ WARNING: Firewall not active after 30s - proceeding anyway"
  echo "⚠ VPN Watchdog will monitor firewall status"
  exit 0  # Do not block system boot
'';
```

With:
```nix
ExecStartPre = pkgs.writeShellScript "vpn-pre-check" ''
  # Wait for firewall to be active (max 30s)
  for i in $(seq 1 30); do
    if systemctl is-active --quiet firewall.service; then
      # Verify nftables firewall rules are loaded (DROP policy active)
      if ${pkgs.nftables}/bin/nft list table inet filter 2>/dev/null | grep -q "policy drop"; then
        echo "✓ Firewall active with DROP policy - safe to start VPN"
        exit 0
      fi
    fi
    sleep 1
  done

  # WARNING: Proceed anyway to avoid boot lockup
  # The VPN watchdog will monitor and alert if firewall fails later
  echo "⚠ WARNING: Firewall not active after 30s - proceeding anyway"
  echo "⚠ VPN Watchdog will monitor firewall status"
  exit 0  # Do not block system boot
'';
```

**Step 2: Verify the configuration compiles**

Run: `nix build .#nixosConfigurations.achim-laptop.config.system.build.toplevel --show-trace`
Expected: Build succeeds without errors

**Step 3: Commit**

```bash
git add modules/protonvpn.nix
git commit -m "fix: update VPN pre-check to validate nftables rules

- Replace iptables validation with nftables
- Check for DROP policy in nftables output
- Maintains same boot safety logic

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Update disable-firewall.sh script

**Files:**
- Modify: `disable-firewall.sh:95-129`

**Step 1: Replace iptables commands with nftables**

Replace the entire section "3. Firewall-Regeln zurücksetzen" (lines 95-129) with:

```bash
# ============================================================================
# 3. Firewall-Regeln zurücksetzen
# ============================================================================
log_section "3️⃣  Setze Firewall-Regeln zurück..."

# nftables - flush all rulesets and tables
log_info "Resette nftables..."
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
```

**Step 2: Verify script syntax**

Run: `bash -n disable-firewall.sh`
Expected: No syntax errors

**Step 3: Commit**

```bash
git add disable-firewall.sh
git commit -m "fix: update disable-firewall.sh for nftables

- Replace iptables commands with nftables flush ruleset
- Keep legacy iptables cleanup for safety
- Maintains same emergency disable functionality

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Update test-network-boot.sh

**Files:**
- Modify: `test-network-boot.sh:16-24`

**Step 1: Update firewall validation test**

The test script checks if firewall service is active, which will still work. However, we should also verify nftables rules are loaded.

Replace Test 1 (lines 16-24):
```bash
# Test 1: Check if firewall is active
echo -n "Test 1: Firewall service active... "
if systemctl is-active --quiet firewall.service; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Firewall is not active!"
    FAILED=1
fi
```

With:
```bash
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
```

**Step 2: Verify script syntax**

Run: `bash -n test-network-boot.sh`
Expected: No syntax errors

**Step 3: Commit**

```bash
git add test-network-boot.sh
git commit -m "test: add nftables rule validation to network boot test

- Verify nftables rules are loaded (DROP policy)
- Maintains existing systemd service check
- Ensures firewall rules are active, not just service

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Deploy and test the migration

**Files:**
- System configuration (all modules)

**Step 1: Review all changes**

Run: `git diff HEAD~4 HEAD`
Expected: See all firewall changes from iptables to nftables

**Step 2: Build the new configuration**

Run: `nixos-rebuild build --flake .#achim-laptop --show-trace`
Expected: Build succeeds without errors or warnings

**Step 3: Review the diff**

Run: `nvd diff /run/current-system ./result`
Expected: Shows firewall.service changes, nftables package added

**Step 4: Switch to new configuration**

Run: `sudo nixos-rebuild switch --flake .#achim-laptop`
Expected: Activation succeeds, firewall service restarts

**Step 5: Verify firewall rules are loaded**

Run: `sudo nft list ruleset`
Expected: Shows complete inet filter and ip6 filter tables with DROP policies

**Step 6: Verify VPN is running**

Run: `systemctl status wg-quick-proton0.service`
Expected: Service is active and running

**Step 7: Run network boot test**

Run: `sudo ./test-network-boot.sh`
Expected: ALL TESTS PASSED

**Step 8: Check firewall logs**

Run: `sudo journalctl -u firewall.service -n 50`
Expected: No errors, rules loaded successfully

**Step 9: Test DNS-over-TLS**

Run: `resolvectl query google.com`
Expected: Shows "encrypted transport: yes"

**Step 10: Test VPN connectivity**

Run: `curl https://am.i.mullvad.net/json`
Expected: Shows VPN IP, not your real IP

**Step 11: Commit final verification**

```bash
git commit --allow-empty -m "verify: nftables migration complete and tested

Migration verified:
- nftables rules loaded correctly
- VPN kill switch functional
- DNS-over-TLS bootstrap working
- Network boot test passes
- All security policies intact

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Update MEMORY.md

**Files:**
- Create/Update: `/home/achim/.claude/projects/-home-achim-nixos-config/memory/MEMORY.md`

**Step 1: Add migration note to memory**

Append to MEMORY.md:
```markdown

## Firewall Implementation

### nftables Migration (2026-02-05)

**Change:** Migrated from iptables to nftables for firewall implementation.

**Key Files:**
- `modules/firewall.nix` - Uses networking.nftables instead of networking.firewall
- `modules/protonvpn.nix:66` - VPN pre-check validates nftables rules
- `disable-firewall.sh` - Uses `nft flush ruleset` instead of iptables commands
- `test-network-boot.sh` - Validates nftables rules are loaded

**Testing:**
- Run `sudo nft list ruleset` to see active rules
- Run `sudo ./test-network-boot.sh` to verify network functionality
- Check `resolvectl query` for DNS-over-TLS encryption status

**Important:** All security policies remain identical - this was a 1:1 translation.
```

**Step 2: Verify memory file**

Run: `cat /home/achim/.claude/projects/-home-achim-nixos-config/memory/MEMORY.md`
Expected: Shows updated content with migration notes

**Step 3: Commit memory update**

```bash
git add /home/achim/.claude/projects/-home-achim-nixos-config/memory/MEMORY.md
git commit -m "docs: document nftables migration in memory

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Rollback Plan

If anything fails during deployment:

1. **Immediate rollback:**
   ```bash
   sudo nixos-rebuild switch --flake .#achim-laptop --rollback
   ```

2. **Emergency network access:**
   ```bash
   sudo ./disable-firewall.sh
   ```

3. **Revert git changes:**
   ```bash
   git reset --hard HEAD~6
   ```

---

## Success Criteria

- [ ] All commits completed without errors
- [ ] `nixos-rebuild switch` succeeds
- [ ] `sudo nft list ruleset` shows complete firewall rules
- [ ] `sudo ./test-network-boot.sh` passes all tests
- [ ] VPN connection active and verified
- [ ] DNS-over-TLS working (resolvectl query shows encrypted)
- [ ] No network connectivity issues
- [ ] Firewall logs show no errors
- [ ] Memory documentation updated
