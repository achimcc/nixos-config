# NixOS Configuration - achim-laptop

A security-oriented, declarative NixOS configuration focused on privacy, development productivity, and full reproducibility.

## Table of Contents

- [System Overview](#system-overview)
- [Security Features](#security-features)
- [Installation](#installation)
- [Module Structure](#module-structure)
- [Secrets Management](#secrets-management)
- [Development Environment](#development-environment)
- [Applications](#applications)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## System Overview

| Component | Configuration |
|-----------|---------------|
| **NixOS Version** | 25.05 |
| **Desktop** | GNOME (X11, GDM) |
| **Shell** | Nushell + Starship |
| **Editor** | Neovim (Rust IDE), VSCodium, Zed |
| **VPN** | ProtonVPN (WireGuard, Auto-Connect) |
| **Encryption** | LUKS Full-Disk, Secure Boot |
| **Secrets** | sops-nix (Age-encrypted) |

### Architecture

```
flake.nix                 # Flake Entry Point
├── configuration.nix     # System Configuration
├── home-achim.nix        # User Configuration (Home Manager)
├── hardware-configuration.nix
├── secrets/
│   └── secrets.yaml      # Encrypted Secrets
└── modules/
    ├── network.nix       # NetworkManager, DNS-over-TLS, Firejail
    ├── firewall.nix      # VPN Kill Switch
    ├── protonvpn.nix     # WireGuard Auto-Connect
    ├── desktop.nix       # GNOME Desktop
    ├── audio.nix         # Pipewire
    ├── power.nix         # TLP, Thermald
    ├── sops.nix          # Secret Management
    ├── security.nix      # Kernel Hardening, AppArmor, ClamAV
    ├── secureboot.nix    # Lanzaboote Secure Boot
    └── home/
        ├── gnome-settings.nix  # GNOME Dconf
        └── neovim.nix          # Neovim IDE
```

## Security Features

### Network & VPN

- **VPN Kill Switch**: Firewall blocks all traffic outside the VPN tunnel
- **DNS-over-TLS**: Mullvad DNS (194.242.2.2) with DNSSEC
- **IPv6 disabled**: Completely disabled at kernel level
- **Random MAC addresses**: On every WiFi scan and connection
- **WireGuard Auto-Connect**: VPN connects before login

### Encryption

- **LUKS Full-Disk Encryption**: Entire disk encrypted
- **Secure Boot**: Lanzaboote with custom signing keys
- **sops-nix**: Secrets encrypted in Git repository
- **SSH Commit Signing**: Git commits signed with Ed25519

### Sandboxing & Hardening

- **Firejail**: Tor Browser, LibreWolf, Signal Desktop isolated
- **AppArmor**: Mandatory Access Control enabled
- **Hardened Kernel**: With additional security options
- **ClamAV**: Real-time antivirus scanner for /home
- **Fail2Ban**: Protection against brute-force attacks
- **AIDE**: File Integrity Monitoring for critical system files
- **unhide/chkrootkit**: Rootkit detection (weekly scans)

### Kernel Hardening

```nix
# Enabled protections:
- ASLR maximized
- Kernel pointers hidden
- dmesg restricted
- Kexec disabled
- BPF JIT hardened
- Ptrace restricted
- Core dumps limited
```

### Blacklisted Kernel Modules

Unused and potentially insecure modules are blocked:
- Network protocols: dccp, sctp, rds, tipc
- Filesystems: cramfs, freevxfs, jffs2, hfs, hfsplus, udf
- Firewire: firewire-core, firewire-ohci, firewire-sbp2

## Installation

### Prerequisites

- NixOS 25.05 or newer
- UEFI system with Secure Boot support
- Age key for secrets decryption

### Initial Installation

```bash
# Clone repository
git clone https://github.com/achim/nixos-config.git
cd nixos-config

# Generate Age key (if not present)
mkdir -p /var/lib/sops-nix
age-keygen -o /var/lib/sops-nix/key.txt

# Add public key to .sops.yaml and re-encrypt secrets
# (see Secrets Management)

# Build and activate system
sudo nixos-rebuild switch --flake .#achim-laptop
```

### Setting Up Secure Boot

```bash
# Create Secure Boot keys
sudo sbctl create-keys

# Enroll keys in firmware
sudo sbctl enroll-keys --microsoft

# Rebuild system (signs automatically)
sudo nixos-rebuild switch --flake .#achim-laptop
```

## Module Structure

### network.nix

- NetworkManager with random MAC addresses
- DNS-over-TLS (systemd-resolved)
- Firejail profiles for browsers and messengers
- WiFi auto-connect with sops password

### firewall.nix

VPN Kill Switch with iptables:
- Default Policy: DROP
- Only allows traffic over VPN interfaces (proton0, tun+, wg+)
- DNS only via localhost (127.0.0.53)
- Syncthing only on local network

### protonvpn.nix

WireGuard configuration for ProtonVPN:
- Server: DE#782 (Frankfurt)
- Auto-connect at boot
- Private key from sops

### security.nix

Comprehensive security configuration:
- Hardened Kernel
- AppArmor with enforcement
- ClamAV on-access scanning
- Fail2Ban
- Audit framework

### home/neovim.nix

Neovim as Rust IDE:
- rustaceanvim (LSP, Clippy)
- nvim-cmp (Completion)
- nvim-treesitter (Syntax)
- nvim-dap (Debugging)
- avante.nvim (AI assistance)
- octo.nvim (GitHub integration)
- telescope.nvim (Fuzzy finder)

## Secrets Management

### Stored Secrets

| Secret | Path | Usage |
|--------|------|-------|
| WiFi Password | `wifi/home` | NetworkManager |
| Email Password | `email/posteo` | Thunderbird |
| Anthropic API Key | `anthropic-api-key` | avante.nvim, crush |
| GitHub Token | `github-token` | gh CLI, octo.nvim |
| WireGuard Key | `wireguard-private-key` | ProtonVPN |

### Editing Secrets

```bash
# Edit secrets file (decrypts automatically)
sops secrets/secrets.yaml

# Set a single secret
sops --set '["secret-name"] "secret-value"' secrets/secrets.yaml

# Display a secret
sops -d --extract '["secret-name"]' secrets/secrets.yaml
```

### Adding a New Host

```bash
# Generate host Age key from SSH key
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# Add key to .sops.yaml and re-encrypt secrets
sops updatekeys secrets/secrets.yaml
```

## Development Environment

### Rust

```bash
# Toolchain (via rustup)
rustup default stable
rustup component add rust-analyzer clippy rustfmt

# In Neovim:
# - Automatic completion
# - Clippy on save
# - Debugging with F5
# - Code actions with <leader>ca
```

### Nix

```bash
# LSP: nil
# Formatter: nixpkgs-fmt

# Format on save enabled in VSCodium
```

### Neovim Keybindings

| Binding | Action |
|---------|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `gd` | Go to definition |
| `K` | Hover |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename |
| `<leader>f` | Format |
| `F5` | Debug start/continue |
| `<leader>b` | Breakpoint |
| `<leader>aa` | AI Ask (avante) |
| `<leader>ae` | AI Edit (avante) |
| `<leader>oi` | GitHub Issues |
| `<leader>op` | GitHub PRs |

### AI Tools

```bash
# Anthropic API key is automatically loaded from sops
echo $ANTHROPIC_API_KEY  # Available in nushell

# Tools:
# - avante.nvim (in Neovim)
# - crush (CLI)
# - claude-code (npm install -g @anthropic-ai/claude-code)
```

## Applications

### Browsers (with Firejail)

- **LibreWolf**: Primary browser with uBlock Origin, KeePassXC, ClearURLs
- **Tor Browser**: For anonymous browsing

### Communication

- **Thunderbird**: Email (Posteo, hardened)
- **Signal Desktop**: Messenger (Firejail sandbox)

### Productivity

- **KeePassXC**: Password manager
- **Syncthing**: File synchronization (local, no cloud)
- **Zathura**: PDF viewer (Vim bindings)
- **Portfolio**: Investment portfolio management

### Development

- **Neovim**: Primary editor (Rust IDE)
- **VSCodium**: VS Code without telemetry
- **Zed**: Modern editor

## Maintenance

### Updating the System

```bash
# Update flake inputs
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .#achim-laptop

# Or just test (without activation)
sudo nixos-rebuild test --flake .#achim-laptop
```

### Garbage Collection

Automatically configured:
- Weekly GC
- Keeps last 30 days

Manual:
```bash
# Delete old generations
sudo nix-collect-garbage -d

# Optimize store
nix store optimise
```

### Auto-Updates

Enabled for:
- nixpkgs
- home-manager

Daily at 04:00 (without automatic reboot).

## Security Monitoring

### AIDE (File Integrity Monitoring)

AIDE monitors critical system files for unauthorized changes.

```bash
# Initial database setup (after first rebuild)
sudo mkdir -p /var/lib/aide
sudo aide --init --config=/etc/aide.conf
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Manual integrity check
sudo aide --check --config=/etc/aide.conf

# Update database after legitimate changes
sudo aide --update --config=/etc/aide.conf
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

Automated scan: Daily at 04:30

### Rootkit Detection

Two complementary tools scan for rootkits weekly:

```bash
# unhide - Find hidden processes and ports
sudo unhide sys procall                  # Check for hidden processes
sudo unhide-tcp                          # Check for hidden TCP/UDP ports

# chkrootkit - Rootkit scanner
sudo chkrootkit                          # Full scan
sudo chkrootkit -q                       # Quiet mode (only warnings)
```

Automated scans:
- unhide (processes): Sunday 05:00
- unhide-tcp (ports): Sunday 05:15
- chkrootkit: Sunday 05:30

### Security Logs with journalctl

```bash
# View all security-related logs
journalctl -u aide-check              # AIDE integrity checks
journalctl -u unhide-check            # unhide process scans
journalctl -u unhide-tcp-check        # unhide port scans
journalctl -u chkrootkit-check        # chkrootkit scans
journalctl -u clamav-daemon           # ClamAV antivirus
journalctl -u fail2ban                # Brute-force protection
journalctl -u usbguard                # USB device monitoring

# Real-time monitoring
journalctl -f -u aide-check -u unhide-check -u chkrootkit-check

# Filter by priority (errors and warnings only)
journalctl -p err -u clamav-daemon

# Show logs from last boot
journalctl -b -u fail2ban

# Audit logs (sudo, password changes, SSH)
journalctl _TRANSPORT=audit

# Search for specific security events
journalctl --grep="INFECTED"          # ClamAV detections
journalctl --grep="Warning"           # General warnings
journalctl --grep="blocked"           # USBGuard blocks
```

### Security Timer Status

```bash
# List all security timers
systemctl list-timers | grep -E "aide|unhide|chkrootkit|clamav"

# Check timer details
systemctl status aide-check.timer
systemctl status unhide-check.timer
systemctl status unhide-tcp-check.timer
systemctl status chkrootkit-check.timer
```

### Manual Security Audit

```bash
# Run all security scans immediately
sudo systemctl start aide-check
sudo systemctl start unhide-check
sudo systemctl start unhide-tcp-check
sudo systemctl start chkrootkit-check

# Check results
journalctl -u aide-check --since "5 minutes ago"
journalctl -u unhide-check --since "10 minutes ago"
journalctl -u unhide-tcp-check --since "10 minutes ago"
journalctl -u chkrootkit-check --since "10 minutes ago"
```

## Troubleshooting

### VPN Not Connecting

```bash
# Check status
systemctl status wg-quick-proton0

# View logs
journalctl -u wg-quick-proton0 -f

# Connect manually
sudo wg-quick up proton0
```

### No Internet (Kill Switch Active)

```bash
# Emergency: Temporarily disable firewall
sudo ./disable-firewall.sh

# Or manually:
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -F
```

### Secrets Not Available

```bash
# Check sops-nix service
systemctl status sops-nix

# Check Age key
cat /var/lib/sops-nix/key.txt

# Test manual decryption
sops -d secrets/secrets.yaml
```

### Secure Boot Problems

```bash
# Check status
sbctl status

# Show unsigned files
sbctl verify

# Re-sign
sudo sbctl sign-all
```

## License

Private configuration. Use at your own risk.

## Contact

- **Email**: achim.schneider@posteo.de
- **Git Signing Key**: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxoCdoA7621jMhv0wX3tx66NEZMv9tp8xdE76sEfjBI
