# NixOS Boot Fix - Test Plan (2026-02-09)

## Problem
System rebootete während laufendem Betrieb. Aktueller Build bootet nicht mehr, musste alte Generation verwenden.

## Root Cause
**Hostname Mismatch**: `flake.nix` definierte `nixosConfigurations.achim-laptop`, aber `networking.hostName = "nixos"` → nixos-rebuild konnte Konfiguration nicht finden.

## Applied Fixes

### 1. Critical: Fixed flake.nix configuration name
- Changed: `nixosConfigurations.achim-laptop` → `nixosConfigurations.nixos`
- Reason: Must match `networking.hostName` in network.nix
- Status: ✅ Build successful

### 2. Fixed DNS-Watchdog timing issue
- Added service dependencies: `after = ["network-online.target", "systemd-resolved.service"]`
- Increased boot delay: 30s → 60s
- Reason: DNS-over-TLS needs time to establish connections
- Status: ✅ Configured

## Safe Testing Procedure

### Step 1: Test build (no reboot)
```bash
cd ~/nixos-config
nixos-rebuild test
```
**Expected**: Switch succeeds, no errors
**Rollback**: If it fails, just reboot - system will boot to old generation

### Step 2: Verify critical services
```bash
# Check DNS is working
resolvectl query example.com

# Check DNS-over-TLS is active
resolvectl status | grep -i tls

# Check firewall is active
sudo nft list ruleset | grep -c "chain"

# Check VPN can connect
sudo protonvpn-cli status
```

### Step 3: Permanent switch (creates boot entry)
Only proceed if Step 1 and 2 succeeded!
```bash
sudo nixos-rebuild switch
```

### Step 4: Test reboot
```bash
sudo reboot
```

## Rollback Instructions

If boot fails:
1. Boot menu will appear automatically
2. Select previous generation (currently running one)
3. System will boot to working state

## Known Issues (Not Fixed)

### i915 GPU Errors
- `i915 0000:00:02.0: [drm] *ERROR* GT0: Enabling uc failed (-5)`
- This is a known Meteor Lake GPU kernel bug (documented in MEMORY.md)
- Mitigations already in place:
  - `GSK_RENDERER=gl` (force OpenGL, avoid Vulkan)
  - Hardware watchdog enabled (auto-reboot on GPU hang)
  - All i915 power-saving features disabled

This will cause occasional warnings in logs but should not prevent boot.
