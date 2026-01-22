# NixOS Konfiguration - achim-laptop

Eine sicherheitsorientierte, deklarative NixOS-Konfiguration mit Fokus auf Privatsphäre, Entwicklungsproduktivität und vollständiger Reproduzierbarkeit.

## Inhaltsverzeichnis

- [Systemübersicht](#systemübersicht)
- [Sicherheitsfeatures](#sicherheitsfeatures)
- [Installation](#installation)
- [Modulstruktur](#modulstruktur)
- [Secrets Management](#secrets-management)
- [Entwicklungsumgebung](#entwicklungsumgebung)
- [Anwendungen](#anwendungen)
- [Wartung](#wartung)
- [Fehlerbehebung](#fehlerbehebung)

## Systemübersicht

| Komponente | Konfiguration |
|------------|---------------|
| **NixOS Version** | 25.05 |
| **Desktop** | GNOME (X11, GDM) |
| **Shell** | Nushell + Starship |
| **Editor** | Neovim (Rust IDE), VSCodium, Zed |
| **VPN** | ProtonVPN (WireGuard, Auto-Connect) |
| **Verschlüsselung** | LUKS Full-Disk, Secure Boot |
| **Secrets** | sops-nix (Age-verschlüsselt) |

### Architektur

```
flake.nix                 # Flake Entry Point
├── configuration.nix     # System-Konfiguration
├── home-achim.nix        # User-Konfiguration (Home Manager)
├── hardware-configuration.nix
├── secrets/
│   └── secrets.yaml      # Verschlüsselte Secrets
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

## Sicherheitsfeatures

### Netzwerk & VPN

- **VPN Kill Switch**: Firewall blockiert allen Traffic außerhalb des VPN-Tunnels
- **DNS-over-TLS**: Mullvad DNS (194.242.2.2) mit DNSSEC
- **IPv6 deaktiviert**: Auf Kernel-Ebene komplett ausgeschaltet
- **Zufällige MAC-Adressen**: Bei jedem WiFi-Scan und Verbindungsaufbau
- **WireGuard Auto-Connect**: VPN verbindet vor dem Login

### Verschlüsselung

- **LUKS Full-Disk Encryption**: Gesamte Festplatte verschlüsselt
- **Secure Boot**: Lanzaboote mit eigenen Signaturschlüsseln
- **sops-nix**: Secrets verschlüsselt im Git-Repository
- **SSH Commit Signing**: Git-Commits mit Ed25519 signiert

### Sandboxing & Hardening

- **Firejail**: Tor Browser, LibreWolf, Signal Desktop isoliert
- **AppArmor**: Mandatory Access Control aktiviert
- **Hardened Kernel**: Mit zusätzlichen Sicherheitsoptionen
- **ClamAV**: Echtzeit-Virenscanner für /home
- **Fail2Ban**: Schutz vor Brute-Force-Angriffen

### Kernel Hardening

```nix
# Aktivierte Schutzmaßnahmen:
- ASLR maximiert
- Kernel-Pointer versteckt
- dmesg eingeschränkt
- Kexec deaktiviert
- BPF JIT gehärtet
- Ptrace eingeschränkt
- Core Dumps limitiert
```

### Blacklisted Kernel-Module

Ungenutzte und potenziell unsichere Module werden blockiert:
- Netzwerkprotokolle: dccp, sctp, rds, tipc
- Dateisysteme: cramfs, freevxfs, jffs2, hfs, hfsplus, udf
- Firewire: firewire-core, firewire-ohci, firewire-sbp2

## Installation

### Voraussetzungen

- NixOS 25.05 oder neuer
- UEFI-System mit Secure Boot Unterstützung
- Age-Key für Secrets-Entschlüsselung

### Erstinstallation

```bash
# Repository klonen
git clone https://github.com/achim/nixos-config.git
cd nixos-config

# Age-Key generieren (falls nicht vorhanden)
mkdir -p /var/lib/sops-nix
age-keygen -o /var/lib/sops-nix/key.txt

# Public Key zu .sops.yaml hinzufügen und secrets neu verschlüsseln
# (siehe Secrets Management)

# System bauen und aktivieren
sudo nixos-rebuild switch --flake .#achim-laptop
```

### Secure Boot einrichten

```bash
# Secure Boot Keys erstellen
sudo sbctl create-keys

# Keys in Firmware enrollen
sudo sbctl enroll-keys --microsoft

# System neu bauen (signiert automatisch)
sudo nixos-rebuild switch --flake .#achim-laptop
```

## Modulstruktur

### network.nix

- NetworkManager mit zufälligen MAC-Adressen
- DNS-over-TLS (systemd-resolved)
- Firejail-Profile für Browser und Messenger
- WiFi-Autoconnect mit sops-Passwort

### firewall.nix

VPN Kill Switch mit iptables:
- Default Policy: DROP
- Erlaubt nur Traffic über VPN-Interfaces (proton0, tun+, wg+)
- DNS nur über localhost (127.0.0.53)
- Syncthing nur im lokalen Netzwerk

### protonvpn.nix

WireGuard-Konfiguration für ProtonVPN:
- Server: DE#782 (Frankfurt)
- Auto-Connect beim Boot
- Private Key aus sops

### security.nix

Umfassende Sicherheitskonfiguration:
- Hardened Kernel
- AppArmor mit Enforcement
- ClamAV On-Access Scanning
- Fail2Ban
- Audit Framework

### home/neovim.nix

Neovim als Rust IDE:
- rustaceanvim (LSP, Clippy)
- nvim-cmp (Completion)
- nvim-treesitter (Syntax)
- nvim-dap (Debugging)
- avante.nvim (AI-Assistenz)
- octo.nvim (GitHub Integration)
- telescope.nvim (Fuzzy Finder)

## Secrets Management

### Gespeicherte Secrets

| Secret | Pfad | Verwendung |
|--------|------|------------|
| WiFi-Passwort | `wifi/home` | NetworkManager |
| E-Mail-Passwort | `email/posteo` | Thunderbird |
| Anthropic API Key | `anthropic-api-key` | avante.nvim, crush |
| GitHub Token | `github-token` | gh CLI, octo.nvim |
| WireGuard Key | `wireguard-private-key` | ProtonVPN |

### Secrets bearbeiten

```bash
# Secrets-Datei bearbeiten (entschlüsselt automatisch)
sops secrets/secrets.yaml

# Einzelnes Secret setzen
sops --set '["secret-name"] "secret-value"' secrets/secrets.yaml

# Secret anzeigen
sops -d --extract '["secret-name"]' secrets/secrets.yaml
```

### Neuen Host hinzufügen

```bash
# Host Age-Key aus SSH-Key generieren
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# Key zu .sops.yaml hinzufügen und secrets neu verschlüsseln
sops updatekeys secrets/secrets.yaml
```

## Entwicklungsumgebung

### Rust

```bash
# Toolchain (via rustup)
rustup default stable
rustup component add rust-analyzer clippy rustfmt

# In Neovim:
# - Automatische Completion
# - Clippy on Save
# - Debugging mit F5
# - Code Actions mit <leader>ca
```

### Nix

```bash
# LSP: nil
# Formatter: nixpkgs-fmt

# Format on Save in VSCodium aktiviert
```

### Neovim Keybindings

| Binding | Aktion |
|---------|--------|
| `<leader>ff` | Dateien suchen |
| `<leader>fg` | Live Grep |
| `gd` | Go to Definition |
| `K` | Hover |
| `<leader>ca` | Code Actions |
| `<leader>rn` | Rename |
| `<leader>f` | Format |
| `F5` | Debug Start/Continue |
| `<leader>b` | Breakpoint |
| `<leader>aa` | AI Ask (avante) |
| `<leader>ae` | AI Edit (avante) |
| `<leader>oi` | GitHub Issues |
| `<leader>op` | GitHub PRs |

### AI-Tools

```bash
# Anthropic API Key wird automatisch aus sops geladen
echo $ANTHROPIC_API_KEY  # Verfügbar in nushell

# Tools:
# - avante.nvim (in Neovim)
# - crush (CLI)
# - claude-code (npm install -g @anthropic-ai/claude-code)
```

## Anwendungen

### Browser (mit Firejail)

- **LibreWolf**: Primärer Browser mit uBlock Origin, KeePassXC, ClearURLs
- **Tor Browser**: Für anonymes Surfen

### Kommunikation

- **Thunderbird**: E-Mail (Posteo, hardened)
- **Signal Desktop**: Messenger (Firejail-Sandbox)

### Produktivität

- **KeePassXC**: Passwort-Manager
- **Syncthing**: Dateisynchronisation (lokal, ohne Cloud)
- **Zathura**: PDF-Viewer (Vim-Bindings)
- **Portfolio**: Wertpapierdepot-Verwaltung

### Entwicklung

- **Neovim**: Haupteditor (Rust IDE)
- **VSCodium**: VS Code ohne Telemetrie
- **Zed**: Moderner Editor

## Wartung

### System aktualisieren

```bash
# Flake-Inputs aktualisieren
nix flake update

# System neu bauen
sudo nixos-rebuild switch --flake .#achim-laptop

# Oder nur testen (ohne Aktivierung)
sudo nixos-rebuild test --flake .#achim-laptop
```

### Garbage Collection

Automatisch konfiguriert:
- Wöchentliche GC
- Behält letzte 30 Tage

Manuell:
```bash
# Alte Generationen löschen
sudo nix-collect-garbage -d

# Store optimieren
nix store optimise
```

### Auto-Updates

Aktiviert für:
- nixpkgs
- home-manager

Täglich um 04:00 Uhr (ohne automatischen Reboot).

## Fehlerbehebung

### VPN verbindet nicht

```bash
# Status prüfen
systemctl status wg-quick-proton0

# Logs anzeigen
journalctl -u wg-quick-proton0 -f

# Manuell verbinden
sudo wg-quick up proton0
```

### Kein Internet (Kill Switch aktiv)

```bash
# Notfall: Firewall temporär deaktivieren
sudo ./disable-firewall.sh

# Oder manuell:
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -F
```

### Secrets nicht verfügbar

```bash
# sops-nix Service prüfen
systemctl status sops-nix

# Age-Key prüfen
cat /var/lib/sops-nix/key.txt

# Secrets manuell entschlüsseln testen
sops -d secrets/secrets.yaml
```

### Secure Boot Probleme

```bash
# Status prüfen
sbctl status

# Nicht signierte Dateien anzeigen
sbctl verify

# Neu signieren
sudo sbctl sign-all
```

## Lizenz

Private Konfiguration. Verwendung auf eigene Gefahr.

## Kontakt

- **E-Mail**: achim.schneider@posteo.de
- **Git Signing Key**: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxoCdoA7621jMhv0wX3tx66NEZMv9tp8xdE76sEfjBI
