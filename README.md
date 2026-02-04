# NixOS Configuration - nixos

A **security-hardened**, declarative NixOS configuration focused on privacy, anonymity, and full reproducibility.

**🔒 Sicherheitsscore: 9.5/10** | [Security Hardening Details](docs/SECURITY-HARDENING.md)

## Table of Contents

- [System Overview](#system-overview)
- [Security Features](#security-features)
- [Installation](#installation)
- [Module Structure](#module-structure)
- [Secrets Management](#secrets-management)
- [Development Environment](#development-environment)
- [CLI Tools](#cli-tools)
- [Applications](#applications)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## System Overview

| Component | Configuration |
|-----------|---------------|
| **NixOS Version** | 25.05 |
| **Desktop** | GNOME (Wayland, GDM) |
| **Shell** | Nushell + Starship + Modern Unix Tools |
| **Editor** | Neovim (Rust IDE), VSCodium, Zed |
| **VPN** | ProtonVPN (WireGuard, Auto-Connect, Kill-Switch) |
| **Encryption** | LUKS2 Full-Disk + FIDO2 + TPM 2.0 + Secure Boot |
| **Secrets** | sops-nix (Age-encrypted) |
| **Hardware Key** | Nitrokey 3C NFC (FIDO2, SSH, OpenPGP, TOTP) |
| **Kernel** | Hardened Kernel + Memory Hardening + Lockdown Mode |
| **Anonymity** | IPv6 disabled, Hostname randomized, No mDNS Broadcasting |

### Architecture

```
flake.nix                 # Flake Entry Point (gepinnte Inputs)
├── configuration.nix     # System Configuration
├── home.nix        # User Configuration (Home Manager)
├── hardware-configuration.nix
├── secrets/
│   └── secrets.yaml      # Encrypted Secrets (Age)
├── pkgs/
│   └── default.nix       # Custom packages overlay
└── modules/
    ├── network.nix       # NetworkManager, DNS-over-TLS, Anonymity, Firejail
    ├── firewall.nix      # VPN Kill Switch + Port-Scan Detection
    ├── firewall-zones.nix # Network Segmentation Zones
    ├── protonvpn.nix     # WireGuard Auto-Connect
    ├── desktop.nix       # GNOME Desktop (Wayland)
    ├── audio.nix         # PipeWire
    ├── power.nix         # TLP, Thermald
    ├── sops.nix          # Secret Management (Age)
    ├── security.nix      # Kernel Hardening, AppArmor, ClamAV, USBGuard, Swappiness
    ├── secureboot.nix    # Lanzaboote + TPM2 + Secure Boot Monitoring
    ├── suricata.nix      # Intrusion Detection System (IDS)
    ├── logwatch.nix      # Automated Security Monitoring & Daily Reports
    ├── ssh-hardening.nix # SSH Server Hardening (prepared, disabled)
    └── home/
        ├── gnome-settings.nix  # GNOME Dconf (Privacy, Screen Lock)
        └── neovim.nix          # Neovim IDE
```

## Security Features

> **📚 Detaillierte Dokumentation**: [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md)

### Anonymity & Privacy (NEW)

- **🆕 IPv6 komplett deaktiviert**: Verhindert VPN-Bypass und DNS-Leaks
- **🆕 Hostname anonymisiert**: Generischer Hostname "nixos" (kein personalisierter Name)
- **🆕 Kein DHCP Hostname**: NetworkManager sendet keinen Hostname
- **🆕 mDNS-Broadcasting deaktiviert**: Avahi Publishing aus (kein .local Broadcasting)
- **🆕 Browser Anti-Fingerprinting**: WebGL aus, WebRTC aus, Letterboxing, First-Party Isolation
- **Random MAC addresses**: Bei jedem WiFi-Scan und jeder Verbindung

### Network & VPN

- **VPN Kill Switch**: Firewall blocks all traffic outside the VPN tunnel
- **🆕 Port-Scan Detection**: Blockiert nach 10 Verbindungen in 60 Sekunden
- **DNS-over-TLS NUR über VPN**: Port 853 nur über VPN-Interfaces (verhindert DNS-Leaks)
- **🆕 Kein Fallback-DNS**: Explizit leer (verhindert DNS-Leaks bei VPN-Ausfall)
- **🆕 Lokales Netzwerk restriktiv**: Nur DHCP zum Router, kein Ping, kein Web-Interface
- **DoT Port-Einschränkung**: Port 853 nur zu Mullvad DNS (verhindert Daten-Exfiltration)
- **Firewall-Logging optimiert**: 1/min Rate-Limit (DoS-Schutz)
- **WireGuard Auto-Connect**: VPN verbindet sich vor dem Login

### Encryption & Authentication

- **LUKS2 Full-Disk Encryption**: Mit FIDO2 (Nitrokey 3C NFC) + Passwort-Fallback
- **🆕 Swap Hardening**: Verschlüsselt mit FIDO2, allowDiscards=false (keine Metadata-Leaks)
- **🆕 Swappiness minimiert**: vm.swappiness=1 (sensitive Daten bleiben im RAM)
- **TPM2 Support**: Optionales automatisches LUKS-Unlock via TPM2
- **Secure Boot**: Lanzaboote mit eigenen Signatur-Keys
- **🆕 Secure Boot Monitoring**: Automatische Verifikation nach jedem Boot
- **sops-nix**: Secrets mit Age verschlüsselt im Git Repository
- **SSH Commit Signing**: Git Commits mit Ed25519 Security Key signiert
- **FIDO2 PAM**: sudo, login und GDM mit Nitrokey + PIN als Alternative zum Passwort

### Sandboxing & Hardening

- **Firejail**: Tor Browser, LibreWolf, Spotify, Discord, FreeTube, Thunderbird, KeePassXC, Logseq, VSCodium, Evince, Newsflash isoliert
- **AppArmor**: Mandatory Access Control mit Enforcement (`killUnconfinedConfinables = true`)
- **Hardened Kernel**: `linuxPackages_hardened` mit zusätzlichen sysctl-Parametern
- **Kernel Module Locking**: Verhindert Runtime-Laden von Kernel-Modulen (Rootkit-Schutz)
- **USBGuard**: USB-Geräte-Autorisierung (blockiert unbekannte Geräte)
- **ClamAV**: Echtzeit-Antivirus mit aktiver Prävention (`OnAccessPrevention = yes`)
- **Fail2Ban**: Schutz gegen Brute-Force (exponentieller Backoff, max 48h)
- **AIDE**: File Integrity Monitoring für kritische Systemdateien
- **unhide/chkrootkit**: Rootkit-Erkennung (wöchentliche Scans)
- **Audit Framework**: Überwachung von sudo, su, Passwort-Änderungen, SSH-Config

### Intrusion Detection & Monitoring

- **Suricata IDS**: Network Intrusion Detection System mit automatischen Regel-Updates
- **Logwatch**: Automatisierte Sicherheitsberichte und kritische Alarmierung
- **Daily Security Reports**: Tägliche Berichte um 06:00 gespeichert in `/var/log/security-reports/`
- **Critical Alert Monitoring**: Prüft alle 5 Minuten auf kritische Sicherheitsereignisse

### Network Segmentation

- **Firewall Zones Architecture**: Netzwerksegmentierung mit dedizierten Zonen
- **Local Network Restrictions**: Lokaler Zugriff nur zu Router und ICMP
- **VPN Zone Separation**: Getrennte Behandlung von lokalem und VPN-Traffic

### Screen Lock & Session

- **Idle-Timeout**: Bildschirmschoner nach 5 Minuten Inaktivität
- **Sofortige Sperre**: Screen Lock greift sofort bei Screensaver-Aktivierung
- **Keine Benachrichtigungen**: Auf dem Sperrbildschirm ausgeblendet

### Kernel Hardening

**🆕 Erweiterte Boot-Parameter**:
```
- IOMMU aktiviert (intel_iommu=on, DMA-Schutz)
- init_on_alloc=1 (Speicher bei Allokation nullen)
- init_on_free=1 (Speicher bei Freigabe nullen)
- page_alloc.shuffle=1 (Page-Allocator randomisieren)
- randomize_kstack_offset=on (Kernel-Stack ASLR)
- slab_nomerge (Anti-Exploit)
- lockdown=confidentiality (Höchster Lockdown-Level)
- vsyscall=none (Legacy-Syscalls deaktiviert)
- mitigations=auto,nosmt (CPU-Mitigations + SMT aus)
```

**Sysctl Hardening**:
```
- ASLR maximiert (randomize_va_space=2)
- Kernel Pointer versteckt (kptr_restrict=2)
- dmesg nur für root (dmesg_restrict=1)
- Kexec deaktiviert
- BPF JIT gehärtet
- Ptrace eingeschränkt (yama.ptrace_scope=1)
- Core Dumps deaktiviert (suid_dumpable=0)
- Unprivilegierte BPF deaktiviert
- TCP Timestamps deaktiviert (OS-Fingerprinting-Schutz)
- SYN Cookies aktiviert
- Source Routing deaktiviert
- ICMP Redirects ignoriert
- Kernel Module Locking aktiviert (lockKernelModules = true)
- 🆕 Swappiness minimiert (vm.swappiness=1)
```

### Blacklisted Kernel Modules

Ungenutzte und potenziell unsichere Module sind blockiert:
- Netzwerk-Protokolle: dccp, sctp, rds, tipc
- Dateisysteme: cramfs, freevxfs, jffs2, hfs, hfsplus, udf
- Firewire: firewire-core, firewire-ohci, firewire-sbp2

### Supply Chain Security

- **Flake-Inputs gepinnt**: sops-nix und rcu auf geprüfte Commit-Hashes fixiert
- **VSCodium Extensions via Nix**: Versioniert und reproduzierbar
- **🆕 Update-Benachrichtigungen**: Tägliche Prüfung, Benachrichtigung bei verfügbaren Updates (keine Auto-Installation)

### SSH Server (Prepared, Disabled)

**🆕 SSH-Hardening-Modul vorbereitet** (ssh-hardening.nix):
- SSH aktuell deaktiviert (enable = false)
- Vollständige Härtungs-Konfiguration für zukünftige Aktivierung
- Nur Key-Authentifizierung, Root-Login verboten
- Moderne Crypto (ChaCha20, Curve25519)
- Alle Forwarding-Features deaktiviert
- Fail2ban SSH-Jail automatisch aktiv bei Aktivierung

## Installation

### Prerequisites

- NixOS 25.05 or newer
- UEFI system with Secure Boot support
- Age key for secrets decryption
- Nitrokey 3C NFC (optional, für FIDO2)

### Initial Installation

```bash
# Clone repository
git clone https://github.com/user/nixos-config.git
cd nixos-config

# Generate Age key (if not present)
mkdir -p /var/lib/sops-nix
age-keygen -o /var/lib/sops-nix/key.txt

# Add public key to .sops.yaml and re-encrypt secrets
# (see Secrets Management)

# Build and activate system
sudo nixos-rebuild switch --flake .#nixos
```

### Setting Up Secure Boot

```bash
# Create Secure Boot keys
sudo sbctl create-keys

# Enroll keys in firmware
sudo sbctl enroll-keys --microsoft

# Rebuild system (signs automatically)
sudo nixos-rebuild switch --flake .#nixos
```

## Module Structure

### network.nix

- NetworkManager mit zufälligen MAC-Adressen
- DNS-over-TLS (systemd-resolved, Mullvad DNS, DNSSEC)
- Firejail-Profile für Browser und Messenger
- WiFi Auto-Connect mit sops-Passwort

### firewall.nix

VPN Kill Switch mit iptables (IPv4 + IPv6):
- Default Policy: DROP
- Traffic nur über VPN-Interfaces (proton0, tun+, wg+)
- DNS nur via localhost (127.0.0.53 / ::1)
- DoT (Port 853) nur zu Mullvad DNS (194.242.2.2)
- Firewall-Logging: Verworfene Pakete mit Rate-Limiting (5/min)
- Syncthing nur im lokalen Netzwerk + über VPN

### protonvpn.nix

WireGuard-Konfiguration für ProtonVPN:
- Auto-Connect beim Boot (vor Display Manager)
- Private Key aus sops
- AllowedIPs: IPv4 + IPv6 (kein IPv6-Leak)
- Automatischer Neustart bei Verbindungsabbruch

### security.nix

Umfassende Sicherheitskonfiguration:
- Gehärteter Kernel mit sysctl-Tuning
- AppArmor mit Enforcement (killUnconfinedConfinables)
- ClamAV mit Echtzeit-Scanning und aktiver Prävention
- Fail2Ban mit exponentiellem Backoff
- Audit Framework für Incident Response
- USBGuard mit Default-Deny
- AIDE File Integrity Monitoring
- Rootkit-Erkennung (unhide, chkrootkit)
- FIDO2/Nitrokey PAM-Authentifizierung

### home/neovim.nix

Neovim als Rust IDE:
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
| Email Password | `email/posteo` | Thunderbird, GNOME Keyring |
| Anthropic API Key | `anthropic-api-key` | avante.nvim, crush, claude-code |
| GitHub Token | `github-token` | gh CLI, octo.nvim |
| WireGuard Key | `wireguard-private-key` | ProtonVPN |
| VPN Endpoint | `protonvpn/endpoint` | WireGuard Config |
| VPN Public Key | `protonvpn/publickey` | WireGuard Config |
| ProtonVPN IP Ranges | `protonvpn/ip-ranges` | Firewall Zones |
| Admin Email | `system/admin-email` | Logwatch Security Reports |
| SSH Key (Hetzner) | `ssh/hetzner-vps` | SSH |
| Miniflux Credentials | `miniflux/*` | Newsflash RSS-Reader |

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
# Toolchain aus nixpkgs-unstable (deklarativ verwaltet):
# cargo, rustc, rust-analyzer, clippy, rustfmt
# cargo-nextest (Test Runner), cargo-depgraph (Dependency Graph)

# In Neovim:
# - Automatische Completion
# - Clippy on save
# - Debugging mit F5
# - Code Actions mit <leader>ca

# In VSCodium:
# - rust-analyzer + clippy
# - LLDB Debugging
# - TangleGuard (Dependency Graph Visualisierung)
```

### Nix

```bash
# LSP: nil
# Formatter: nixpkgs-fmt
# Format on save in VSCodium aktiviert
```

### VSCodium Extensions

| Extension | Funktion |
|-----------|----------|
| nix-ide | Nix Language Support |
| rust-analyzer | Rust LSP |
| even-better-toml | TOML Syntax |
| vscode-lldb | Rust Debugging |
| tinymist | Typst Language Support |
| crates | Crate-Versionen in Cargo.toml |
| direnv | direnv Integration |
| errorlens | Inline Error Annotations |
| continue | AI Pair Programming |
| cline (claude-dev) | AI Coding Assistant |
| markdown-all-in-one | Markdown Support |
| vscode-markdownlint | Markdown Linting |
| pdf | PDF Preview |
| TangleGuard | Dependency Graph Visualisierung (autoPatchelfHook) |

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
# Anthropic API key wird automatisch aus sops geladen
echo $ANTHROPIC_API_KEY  # Verfügbar in nushell

# Tools:
# - avante.nvim (in Neovim)
# - crush (CLI)
# - claude-code (npm install -g @anthropic-ai/claude-code)
# - continue (VSCodium Extension)
# - cline (VSCodium Extension)
# - aider-chat (CLI)
```

## CLI Tools

Modern Unix Ersetzungen mit besserer UX, Performance und Features.

### Modern Unix Essentials

| Tool | Command | Replaces | Feature |
|------|---------|----------|---------|
| **ripgrep** | `rg` | grep | Schnellste Suche, respektiert .gitignore |
| **bat** | `bat` | cat | Syntax-Highlighting, Git Integration |
| **eza** | `eza` | ls | Icons, Farben, Git-Status, Baumansicht |
| **zoxide** | `z` | cd | Intelligentes Verzeichnis-Springen |
| **fd** | `fd` | find | Intuitive Syntax, ignoriert node_modules |
| **yazi** | `yazi` | ranger/nnn | Terminal-Dateimanager mit Bildvorschau |

### Monitoring & Network

| Tool | Command | Replaces | Feature |
|------|---------|----------|---------|
| **bottom** | `btm` | top/htop | Grafischer Prozess-Monitor |
| **mission-center** | GUI | gnome-system-monitor | CPU, RAM, Disk, GPU Monitor |
| **xh** | `xh` | curl | HTTP Client mit JSON Formatting |
| **dust** | `dust` | du | Visuelle Festplattenbelegung |
| **baobab** | GUI | - | GNOME Disk Usage Analyzer |

### Git Tools

| Tool | Command | Feature |
|------|---------|---------|
| **gitui** | `gitui` | Terminal UI für Git |
| **delta** | (pager) | Syntax-Highlighting für Diffs |
| **glab** | `glab` | GitLab CLI |

### Shell Aliases

Alle Tools sind in Nushell für nahtlose Ersetzung aliased:

```bash
ls   → eza --icons
ll   → eza -l --icons --git
la   → eza -la --icons --git
lt   → eza --tree --icons
cat  → bat
grep → rg
find → fd
top  → btm
du   → dust
z    → zoxide (smart cd)
gs   → git status
gc   → git commit
gp   → git push
nrs  → sudo nixos-rebuild switch --flake ...#nixos
```

## Applications

### Browsers

#### Mullvad Browser (Primary - Maximum Anti-Fingerprinting)

**Eigenschaften:**
- Basiert auf Tor Browser Technologie (ohne Tor-Netzwerk)
- Optimiert für minimalen Fingerprint - alle Nutzer sehen identisch aus
- Integriertes Anti-Fingerprinting (keine Konfiguration nötig)
- **Fingerprint-Score:** ~1 in 10-100 (vs LibreWolf: ~1 in 150,000)

**⚠️ Wichtig: Keine Extensions verwenden!**
- Extensions machen dich uniquer und zerstören den Fingerprint-Schutz
- Mullvad Browser ist für Nutzung OHNE Extensions konzipiert
- Für Bitwarden/Extensions: LibreWolf verwenden

**Konfiguration:**
```bash
# Profile-Verzeichnis
~/.mullvad/Browser/

# Minimale user.js (nur Usability, keine Fingerprint-Änderungen)
# Wird automatisch via home-manager erstellt
```

**Fingerprint-Test:**
```bash
# Nach dem Rebuild: https://coveryourtracks.eff.org testen
# Erwartetes Ergebnis: "Your browser does not appear to be unique"
```

#### LibreWolf (Secondary - Privacy mit Extensions)

**Eigenschaften:**
- Privacy-Browser mit Extensions-Support (Firejail-gesandboxt)
- Guter Kompromiss zwischen Privacy und Funktionalität
- Extensions: uBlock Origin, Bitwarden, ClearURLs, Multi-Account Containers
- **Fingerprint-Score:** ~1 in 150,000 (mit aktueller Konfiguration)

**Verwendung:**
- Für Webapps, die Extensions benötigen (Bitwarden)
- Alltägliches Browsen mit bekannten Websites
- Banking, Shopping (wo Login erforderlich)

**Konfiguration:**
- Deklarativ via `programs.librewolf` in home.nix
- Maximum Anti-Fingerprinting Settings aktiv
- Font-Visibility API, Windows User-Agent Spoofing, etc.

#### Tor Browser (Anonymity - Over Tor Network)

**Eigenschaften:**
- Für anonymes Browsen über Tor-Netzwerk (Firejail-gesandboxt)
- Privates Downloads-Verzeichnis
- Maximale Anonymität, aber langsamer

**Verwendung:**
- Hochsensible Recherchen
- Anonyme Kommunikation
- Bypass von Geo-Blocking

### Communication (Firejail / Flatpak)

- **Thunderbird**: Email (Posteo, gehärtet, Firejail) -- Remote Images deaktiviert, JS deaktiviert
- **Flare**: Signal-Client (GTK/libadwaita, Flatpak)
- **Discord**: Chat-Client (Firejail)

### Media & Audio

- **Spotify**: Musik-Streaming (Firejail)
- **Amberol**: GNOME Musik-Player für lokale Audiodateien
- **Shortwave**: Internet-Radio (radio-browser.info)
- **Celluloid**: GTK-Frontend für mpv (Video)
- **FreeTube**: YouTube-Client ohne Tracking (Firejail)
- **Helvum**: GTK Patchbay für PipeWire
- **EasyEffects**: Equalizer & Audio-Effekte (mit JackHack96 Presets)

### Lesen & Notizen

- **Evince**: GNOME Document Viewer (benutzerfreundlich, Firejail-gesandboxt)
- **Foliate**: E-Book-Reader (EPUB, MOBI, FB2)
- **Rnote**: Handschriftliche Notizen und Skizzen
- **Apostrophe**: Distraction-free Markdown-Editor
- **Logseq**: Wissensmanagement / Personal Wiki (Firejail)

### Password Management

- **Bitwarden Desktop**: Passwort-Manager mit Browser-Biometrics (Native Messaging zu LibreWolf)
- **KeePassXC**: Offline Passwort-Manager (Firejail)

### Productivity & Tools

- **Syncthing**: Dateisynchronisation (lokal + eigener Relay-Server)
- **Portfolio Performance**: Investment Portfolio (Flatpak)
- **Denaro**: Persönliche Finanzverwaltung (Flatpak)
- **Newsflash**: RSS-Reader mit Miniflux-Sync

### System & Utilities

- **Mission Center**: System-Monitor (CPU, RAM, Disk, GPU)
- **Baobab**: Grafische Festplattenbelegung
- **Czkawka**: Duplikate-Finder (Dateien, ähnliche Bilder, leere Ordner)
- **Raider**: Sicheres Löschen von Dateien
- **TextSnatcher**: OCR -- Text aus Bildern/Screenshots kopieren
- **Blackbox Terminal**: GTK4-Terminalemulator

### Download Manager

- **Motrix**: Download-Manager (HTTP, FTP, BitTorrent, Magnet)
- **Fragments**: GNOME BitTorrent-Client
- **Parabolic**: Video/Audio-Downloader (yt-dlp Frontend)
- **JDownloader 2**: Download-Manager (Flatpak)

### Entwicklung

- **Neovim**: Primary Editor (Rust IDE)
- **VSCodium**: VS Code ohne Telemetrie (Firejail, 14 Extensions)
- **Zed**: Modern Editor
- **Wildcard**: Regex-Tester
- **Elastic**: Spring-Animationen designen

### Firejail-Sandboxed Applications

| App | Profil | Besonderheiten |
|-----|--------|----------------|
| LibreWolf | librewolf.profile + .local | Bitwarden Native Messaging, FIDO2, Portal-Zugriff |
| Tor Browser | tor-browser.profile | Private Downloads-Verzeichnis |
| Spotify | spotify.profile + .local | MPRIS, OAuth-Login |
| Discord | discord.profile | Standard-Profil |
| FreeTube | freetube.profile | Standard-Profil |
| Thunderbird | thunderbird.profile | E-Mail |
| KeePassXC | keepassxc.profile | Passwort-Datenbank |
| Newsflash | newsflash.profile | RSS-Feeds |
| Logseq | obsidian.profile | Whitelist ~/Dokumente/Logseq |
| VSCodium | vscodium.profile | Whitelist ~/Projects, ~/nixos-config |
| Evince | evince.profile | PDF-Dateien |

### Flatpak Applications

Deklarativ verwaltet über `nix-flatpak` mit wöchentlichen Auto-Updates:

| App | Flatpak ID |
|-----|------------|
| Flare (Signal) | de.schmidhuberj.Flare |
| JDownloader 2 | org.jdownloader.JDownloader |
| Portfolio Performance | info.portfolio_performance.PortfolioPerformance |
| Denaro | org.nickvision.money |

## Maintenance

### Updating the System

```bash
# Update flake inputs
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .#nixos

# Or just test (without activation)
sudo nixos-rebuild test --flake .#nixos

# Kurzform (nushell alias)
nrs
```

### Suricata Rule Management

```bash
# Update Suricata rules manually
sudo suricata-update

# List enabled rulesets
sudo suricata-update list-enabled-sources

# Check rule syntax
sudo suricata -T -c /etc/suricata/suricata.yaml

# Restart Suricata after rule updates
sudo systemctl restart suricata
```

Automatische Regel-Updates: Täglich um 03:00

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

**🆕 Neue Update-Strategie**:
- Automatische Updates **deaktiviert** (manuelle Kontrolle)
- Tägliche **Benachrichtigung** bei verfügbaren Updates
- Flake-Updates werden heruntergeladen und committed
- User entscheidet über Rebuild-Zeitpunkt

```bash
# Nach Benachrichtigung: System rebuilden
sudo nixos-rebuild switch --flake .#nixos
```

## Security Monitoring

### Suricata IDS (Intrusion Detection System)

Suricata überwacht den Netzwerkverkehr auf verdächtige Aktivitäten und Angriffsmuster.

```bash
# Status prüfen
systemctl status suricata

# Live-Überwachung der Alerts
sudo tail -f /var/log/suricata/fast.log

# Detaillierte Event-Logs
sudo tail -f /var/log/suricata/eve.json | jq .

# Statistiken anzeigen
sudo suricatasc -c "dump-counters"

# Regel-Update manuell durchführen
sudo suricata-update

# Suricata neu starten (nach Regel-Updates)
sudo systemctl restart suricata
```

Automatische Regel-Updates: Täglich um 03:00

### Logwatch (Automated Security Reports)

Logwatch erstellt tägliche Sicherheitsberichte und überwacht kritische Ereignisse.

```bash
# Tägliche Security Reports
ls -la /var/log/security-reports/

# Letzten Bericht anzeigen
cat /var/log/security-reports/security-report-$(date +%Y-%m-%d).txt

# Manuell Bericht erstellen
sudo logwatch --output file --filename /tmp/security-report.txt --detail High

# Critical Alert Monitor Status
systemctl status logwatch-critical-alerts.timer
journalctl -u logwatch-critical-alerts -f
```

Automatisierung:
- Daily Security Report: Täglich um 06:00 (gespeichert in `/var/log/security-reports/`)
- Critical Alert Monitor: Alle 5 Minuten
- Email-Berichte an: Admin-Email aus sops secrets

### AIDE (File Integrity Monitoring)

AIDE überwacht kritische Systemdateien auf unautorisierte Änderungen.

```bash
# Initiale Datenbank erstellen (nach erstem Rebuild)
sudo mkdir -p /var/lib/aide
sudo aide --init --config=/etc/aide.conf
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Manuelle Integritätsprüfung
sudo aide --check --config=/etc/aide.conf

# Datenbank nach legitimen Änderungen aktualisieren
sudo aide --update --config=/etc/aide.conf
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

Automatisierter Scan: Täglich um 04:30

### Rootkit Detection

Zwei komplementäre Tools scannen wöchentlich nach Rootkits:

```bash
# unhide - Versteckte Prozesse und Ports finden
sudo unhide sys procall                  # Versteckte Prozesse
sudo unhide-tcp                          # Versteckte TCP/UDP Ports

# chkrootkit - Rootkit Scanner
sudo chkrootkit                          # Vollständiger Scan
sudo chkrootkit -q                       # Quiet Mode (nur Warnungen)
```

Automatisierte Scans:
- unhide (Prozesse): Sonntag 05:00
- unhide-tcp (Ports): Sonntag 05:15
- chkrootkit: Sonntag 05:30

### Firewall-Logging

Verworfene Pakete werden mit Rate-Limiting geloggt:

```bash
# Verworfene Pakete anzeigen (IPv4)
journalctl --grep="iptables-dropped"

# Verworfene Pakete anzeigen (IPv6)
journalctl --grep="ip6tables-dropped"

# Echtzeit-Monitoring
journalctl -f --grep="iptables-dropped"
```

### Security Logs mit journalctl

```bash
# Alle sicherheitsrelevanten Logs
journalctl -u aide-check              # AIDE Integritätsprüfungen
journalctl -u unhide-check            # unhide Prozess-Scans
journalctl -u unhide-tcp-check        # unhide Port-Scans
journalctl -u chkrootkit-check        # chkrootkit Scans
journalctl -u clamav-daemon           # ClamAV Antivirus
journalctl -u clamonacc               # ClamAV Echtzeit-Scanner
journalctl -u fail2ban                # Brute-Force Schutz
journalctl -u usbguard                # USB-Geräte-Monitoring

# Echtzeit-Monitoring
journalctl -f -u aide-check -u unhide-check -u chkrootkit-check

# Audit Logs (sudo, Passwort-Änderungen, SSH)
journalctl _TRANSPORT=audit

# ClamAV Erkennungen
journalctl --grep="INFECTED"

# USBGuard blockierte Geräte
journalctl --grep="blocked"
```

### Security Timer Status

```bash
# Alle Security-Timer auflisten
systemctl list-timers | grep -E "aide|unhide|chkrootkit|clamav"

# Timer-Details
systemctl status aide-check.timer
systemctl status unhide-check.timer
systemctl status chkrootkit-check.timer
```

### Manuelles Security Audit

```bash
# Alle Security-Scans sofort starten
sudo systemctl start aide-check
sudo systemctl start unhide-check
sudo systemctl start unhide-tcp-check
sudo systemctl start chkrootkit-check

# Ergebnisse prüfen
journalctl -u aide-check --since "5 minutes ago"
journalctl -u unhide-check --since "10 minutes ago"
journalctl -u chkrootkit-check --since "10 minutes ago"
```

## Troubleshooting

### VPN Not Connecting

```bash
# Status prüfen
systemctl status wg-quick-proton0

# Logs anzeigen
journalctl -u wg-quick-proton0 -f

# Manuell verbinden
sudo wg-quick up proton0
```

### No Internet (Kill Switch Active)

```bash
# Notfall: Firewall temporär deaktivieren
sudo ./disable-firewall.sh

# Oder manuell:
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -F
```

### Secrets Not Available

```bash
# sops-nix Service prüfen
systemctl status sops-nix

# Age Key prüfen
ls -la /var/lib/sops-nix/key.txt

# Manuelle Entschlüsselung testen
sops -d secrets/secrets.yaml
```

### Secure Boot Problems

```bash
# Status prüfen
sbctl status

# Unsignierte Dateien anzeigen
sbctl verify

# Neu signieren
sudo sbctl sign-all
```

### USBGuard: Blocked USB Device

USBGuard blockiert alle neu angeschlossenen USB-Geräte standardmäßig.

```bash
# Alle USB-Geräte auflisten
pkexec usbguard list-devices

# Blockiertes Gerät temporär erlauben
pkexec usbguard list-devices | grep block
pkexec usbguard allow-device 15  # Gerätenummer aus der Liste

# Gerät permanent erlauben: Regel in modules/security.nix hinzufügen
```

Desktop-Benachrichtigungen: `usbguard-notifier` zeigt Popups für blockierte Geräte.

### DNSSEC-Probleme

Falls DNSSEC DNS-Auflösung für bestimmte Domains verhindert:

```bash
# DNSSEC-Status prüfen
resolvectl status

# Temporär auf allow-downgrade setzen (in modules/network.nix):
# dnssec = "allow-downgrade";
```

### AppArmor blockiert Anwendung

```bash
# AppArmor-Status prüfen
sudo aa-status

# Betroffenes Profil identifizieren
journalctl --grep="apparmor.*DENIED"

# Profil temporär in Complain-Modus setzen
sudo aa-complain /path/to/profile
```

## License

Private configuration. Use at your own risk.

## Contact

- **Email**: user@posteo.de
- **Git Signing Key**: sk-ssh-ed25519@openssh.com (Nitrokey 3C NFC)
