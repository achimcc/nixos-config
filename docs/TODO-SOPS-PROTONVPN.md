# TODO: Add ProtonVPN IP Ranges to Sops Secrets

## Status
MANUAL ACTION REQUIRED - This file contains instructions for completing the ProtonVPN IP ranges migration to sops.

## Background
ProtonVPN server IP ranges have been moved from hardcoded values in `modules/firewall.nix` to encrypted sops secrets to prevent revealing VPN usage in git history.

## Required Manual Steps

### 1. Edit the encrypted secrets file
Run the following command to edit the secrets file with sops:

```bash
cd /home/achim/nixos-config
sops secrets/secrets.yaml
```

### 2. Add the ProtonVPN IP ranges secret
In the sops editor, add the following entry to the YAML file:

```yaml
protonvpn:
  ip-ranges: |
    185.159.156.0/22 185.107.56.0/22 146.70.0.0/16 156.146.32.0/20 149.88.0.0/14 193.148.16.0/20 91.219.212.0/22 89.36.76.0/22 37.120.128.0/17 79.127.141.0/24
```

**Important Notes:**
- The IP ranges should be on a single line, space-separated
- Maintain the YAML structure with proper indentation
- These are the official ProtonVPN server IP ranges (source: https://protonvpn.com/support/protonvpn-ip-addresses)

### 3. Save and exit
Save the file in the sops editor (it will be automatically re-encrypted).

### 4. Test the configuration
After adding the secret, rebuild the NixOS configuration:

```bash
sudo nixos-rebuild switch
```

### 5. Verify the firewall rules
Check that the firewall rules are applied correctly:

```bash
sudo iptables -L OUTPUT -v -n | grep -A 10 "protonvpn"
```

You should see OUTPUT rules accepting traffic to the ProtonVPN IP ranges.

### 6. Clean up
Once verified working, delete this TODO file:

```bash
rm /home/achim/nixos-config/docs/TODO-SOPS-PROTONVPN.md
git add docs/TODO-SOPS-PROTONVPN.md
git commit -m "chore: remove completed ProtonVPN sops TODO"
```

## Technical Details

### Files Modified
- `/home/achim/nixos-config/modules/sops.nix` - Added secret definition for `protonvpn/ip-ranges`
- `/home/achim/nixos-config/modules/firewall.nix` - Modified to read IP ranges from sops secret instead of hardcoded values

### Secret Configuration
- **Path**: `${config.sops.secrets."protonvpn/ip-ranges".path}` (typically `/run/secrets/protonvpn/ip-ranges`)
- **Owner**: root
- **Mode**: 0400 (read-only for root)
- **Format**: Space-separated CIDR ranges on a single line

### Fallback Behavior
If the secret file doesn't exist, the firewall will skip the ProtonVPN IP range rules but will still allow VPN connections via the port-based rules (UDP ports 51820, 88, 1224, etc.).

## Security Benefits
- VPN usage is no longer visible in git history
- IP ranges are encrypted at rest in the repository
- Only the system with the correct age key can decrypt the ranges
- Reduces attack surface by obscuring VPN infrastructure details
