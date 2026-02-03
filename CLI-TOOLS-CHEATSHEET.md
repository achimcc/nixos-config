# NixOS CLI Tools Cheat Sheet

Umfassende Dokumentation aller installierten Command-Line Tools auf nixos.

---

## Inhaltsverzeichnis

1. [Shell: Nushell](#shell-nushell)
2. [Modern Unix Tools](#modern-unix-tools)
3. [Git & Version Control](#git--version-control)
4. [Entwicklungstools](#entwicklungstools)
5. [Dateimanagement](#dateimanagement)
6. [Netzwerk & VPN](#netzwerk--vpn)
7. [Sicherheit & Verschlüsselung](#sicherheit--verschlüsselung)
8. [System Monitoring](#system-monitoring)
9. [Editor: Neovim](#editor-neovim)
10. [Nix Package Management](#nix-package-management)
11. [Sonstiges](#sonstiges)

---

## Shell: Nushell

**Standard-Shell** des Systems mit strukturierten Daten und moderner Syntax.

### Grundlagen

```nu
# Hilfe anzeigen
help commands              # Alle verfügbaren Befehle
help <befehl>              # Hilfe zu spezifischem Befehl

# Umgebungsvariablen
$env.PATH                  # PATH anzeigen
$env.EDITOR                # Editor (vim)
$env.ANTHROPIC_API_KEY     # API Key (aus sops Secret)
$env.GH_TOKEN              # GitHub Token (aus sops Secret)

# Navigation
cd ~/Dokumente             # Verzeichnis wechseln
ls                         # Dateien auflisten (Alias zu eza)
pwd                        # Aktuelles Verzeichnis
```

### Datenverarbeitung

```nu
# Pipes und Strukturierte Daten
ls | where size > 1mb                    # Dateien größer als 1MB
ps | where cpu > 50                      # Prozesse mit >50% CPU
sys | get mem                            # Speicherinfo
open Cargo.toml | get dependencies       # TOML parsen

# Tabellen filtern und sortieren
ls | sort-by size                        # Nach Größe sortieren
ls | sort-by modified --reverse          # Neueste zuerst
open data.json | select name age         # Spalten auswählen
```

### Aliase (vorkonfiguriert)

```nu
# Datei-Operationen
ls        # → eza --icons
ll        # → eza -l --icons --git
la        # → eza -la --icons --git
lt        # → eza --tree --icons
cat       # → bat (Syntax-Highlighting)

# Suchtools
grep      # → rg (ripgrep)
find      # → fd

# System
top       # → btm (bottom)
du        # → dust

# Git
gs        # → git status
gc        # → git commit
gp        # → git push

# NixOS
nrs       # → sudo nixos-rebuild switch --flake /home/user/nixos-config#nixos

# Sonstiges
obb       # → openbb (Investment Research)
charge    # → sudo tlp fullcharge (Akku 100% laden)
```

### Integration mit Tools

```nu
# Starship Prompt (aktiviert)
# Zeigt Git-Branch, Status, Sprachen, etc.

# Carapace (Autocomplete)
# Automatische Vervollständigung für 600+ Tools

# Direnv (Projekt-Umgebungen)
# Lädt automatisch .envrc Dateien

# Zoxide (Smart cd)
z <teilname>              # Spring zu häufig genutztem Verzeichnis
zi                        # Interaktive Auswahl mit fzf
```

### Konfiguration

Datei: `~/.config/nushell/config.nu`

```nu
# Banner deaktiviert
$env.config.show_banner = false

# NPM global packages
$env.PATH = ($env.PATH | prepend $"($env.HOME)/.npm-global/bin")

# Secrets aus sops laden
ANTHROPIC_API_KEY aus /run/secrets/anthropic-api-key
GH_TOKEN aus /run/secrets/github-token
```

---

## Modern Unix Tools

Moderne Rust-basierte Alternativen zu klassischen Unix-Tools.

### ripgrep (`rg`)

Extrem schnelle Textsuche (grep-Ersatz).

```bash
# Grundlegende Suche
rg "pattern"                          # Rekursiv im aktuellen Verzeichnis
rg "pattern" path/                    # In bestimmtem Pfad
rg -i "pattern"                       # Case-insensitive
rg -w "word"                          # Nur ganze Wörter

# Erweiterte Optionen
rg -t rust "fn main"                  # Nur in Rust-Dateien
rg -T "*.lock" "pattern"              # Bestimmte Dateien ausschließen
rg --hidden "pattern"                 # In versteckten Dateien suchen
rg -C 3 "pattern"                     # 3 Zeilen Kontext vor/nach
rg -l "pattern"                       # Nur Dateinamen ausgeben
rg --stats "pattern"                  # Statistiken anzeigen

# Mit Regex
rg "fn \w+\(" --type rust             # Funktionsdefinitionen
rg "TODO|FIXME" -i                    # Mehrere Patterns
```

### bat

`cat` mit Syntax-Highlighting und Git-Integration.

```bash
# Grundlegende Nutzung
bat datei.txt                         # Datei mit Highlighting
bat -n datei.txt                      # Mit Zeilennummern
bat --paging=never datei.txt          # Ohne Pager

# Mehrere Dateien
bat file1.rs file2.rs                 # Mehrere Dateien
bat src/**/*.rs                       # Alle Rust-Dateien

# Als cat-Ersatz in Pipes
curl -s api.github.com | bat -l json  # JSON mit Highlighting
```

### eza

Modernes `ls` mit Icons und Git-Status.

```bash
# Basis-Nutzung (über Aliase)
ls                # Icons
ll                # Lange Liste mit Icons und Git-Status
la                # Alle Dateien inkl. versteckte
lt                # Baum-Ansicht

# Direkter Aufruf mit Optionen
eza -lh                               # Lesbare Größen
eza -la --git                         # Mit Git-Status
eza --tree --level=2                  # Baum bis Level 2
eza -l --sort=modified                # Nach Änderungsdatum
eza -l --sort=size                    # Nach Größe
eza --icons --group-directories-first # Ordner zuerst
```

### fd

Schnelles und benutzerfreundliches `find`.

```bash
# Einfache Suche
fd pattern                            # Rekursiv suchen
fd -e rs                              # Nur .rs Dateien
fd -e md -e txt                       # Mehrere Endungen

# Erweiterte Optionen
fd -H pattern                         # Inkl. versteckte Dateien
fd -I pattern                         # Keine .gitignore
fd -t f pattern                       # Nur Dateien
fd -t d pattern                       # Nur Verzeichnisse
fd --changed-within 1d                # Geändert in letzten 24h
fd --size +1m                         # Größer als 1MB

# Mit Exec
fd -e jpg -x convert {} {.}.png       # Alle JPG zu PNG konvertieren
fd -e rs -x wc -l                     # Zeilen zählen in Rust-Dateien
```

### bottom (`btm`)

Grafischer Prozess-Monitor im Terminal.

```bash
btm                                   # Starten (Alias: top)
btm -b                                # Basic mode
btm --battery                         # Mit Akku-Anzeige
btm -t                                # Minimal tree mode

# Tastenkürzel (während btm läuft)
# q     - Beenden
# /     - Suchen
# dd    - Kill-Prozess
# t     - Baum-Ansicht umschalten
# c,m,p - CPU/RAM/Prozess fokussieren
```

### dust

Visualisierte Festplattenbelegung.

```bash
dust                                  # Aktuelles Verzeichnis
dust /home/user                      # Bestimmtes Verzeichnis
dust -d 3                             # Max Tiefe 3
dust -r                               # Umgekehrte Sortierung
dust -n 20                            # Top 20 anzeigen
```

### xh

Moderner HTTP-Client (HTTPie-ähnlich).

```bash
# GET Requests
xh httpbin.org/get                    # Einfacher GET
xh https://api.github.com/users/user # Mit HTTPS

# POST Requests
xh POST httpbin.org/post name=user   # Form data
xh POST httpbin.org/post --json \
   name=user age:=30                 # JSON (`:=` für Zahlen)

# Headers & Auth
xh httpbin.org/headers \
   Authorization:"Bearer TOKEN"       # Custom Header
xh -a user:pass httpbin.org/basic-auth/user/pass # Basic Auth

# Download
xh --download httpbin.org/image/png   # Datei herunterladen
```

---

## Git & Version Control

### Git (Basis-Konfiguration)

```bash
# Identität (vorkonfiguriert)
git config user.name                  # "NixOS User"
git config user.email                 # "user@posteo.de"

# Signierung mit SSH (aktiviert)
git config gpg.format                 # "ssh"
git config commit.gpgSign             # true

# Delta Pager (aktiviert)
git diff                              # Mit Syntax-Highlighting
git log -p                            # Log mit Diffs

# Nützliche Befehle
git pull --rebase                     # Vorkonfiguriert als Standard
git log --oneline --graph             # Kompakter Graph
```

### delta

Syntax-Highlighting für Git Diffs (automatisch als Pager).

```bash
# Automatisch aktiviert für:
git diff
git show
git log -p

# Manuelle Nutzung
diff file1 file2 | delta              # Beliebige Diffs
```

### gitui

Terminal-UI für Git (interaktiv).

```bash
gitui                                 # Starten

# Tastenkürzel
# 1-5   - Tabs wechseln (Status/Log/Files/Stashing/Stashes)
# c     - Commit
# e     - Edit file
# s     - Stage/Unstage
# D     - Discard changes
# P     - Push
# f     - Fetch
# p     - Pull
# h     - Hilfe
# q     - Beenden
```

### GitHub CLI (`gh`)

Offizielle GitHub CLI (OAuth-konfiguriert).

```bash
# Repository
gh repo view                          # Aktuelles Repo anzeigen
gh repo clone owner/repo              # Repo klonen
gh repo create                        # Neues Repo erstellen

# Pull Requests
gh pr list                            # PRs auflisten
gh pr view 123                        # PR #123 anzeigen
gh pr create                          # PR erstellen
gh pr checkout 123                    # PR #123 auschecken
gh pr review 123 --approve            # PR genehmigen
gh pr merge 123                       # PR mergen

# Issues
gh issue list                         # Issues auflisten
gh issue create                       # Issue erstellen
gh issue view 42                      # Issue #42 anzeigen

# Workflows (GitHub Actions)
gh workflow list                      # Workflows auflisten
gh run list                           # Runs anzeigen
gh run view                           # Letzten Run anzeigen

# Konfiguration (bereits authentifiziert)
gh auth status                        # Auth-Status prüfen
```

### GitLab CLI (`glab`)

```bash
# Ähnlich zu gh, aber für GitLab
glab repo clone group/project
glab mr list                          # Merge Requests
glab issue list
glab ci view                          # CI Pipeline
```

---

## Entwicklungstools

### Rust Toolchain (unstable)

```bash
# Compiler & Build
cargo new projekt                     # Neues Projekt
cargo init                            # In bestehendem Verzeichnis
cargo build                           # Debug-Build
cargo build --release                 # Release-Build
cargo run                             # Bauen & Ausführen

# Testing
cargo test                            # Tests ausführen
cargo nextest run                     # Mit nextest (schneller)
cargo nextest run --nocapture         # Mit Ausgaben

# Linting & Formatting
cargo clippy                          # Linter (vorkonfiguriert)
cargo fmt                             # Code formatieren
cargo check                           # Nur Type-Check (schnell)

# Dependencies
cargo add serde                       # Dependency hinzufügen
cargo update                          # Dependencies aktualisieren
cargo tree                            # Dependency-Baum

# Erweiterte Tools
cargo depgraph | dot -Tpng > deps.png # Dependency-Graph
cargo nextest list                    # Tests auflisten
```

**Rust Analyzer:** Automatisch in Neovim und VSCodium integriert.

### Node.js & npm

```bash
# npm (Node.js 22)
npm install -g paket                  # Global installieren
npm install paket                     # Lokal installieren
npm run script                        # Package.json Script

# Global packages Pfad: ~/.npm-global/
# Automatisch in $PATH via Nushell
```

### Python 3

```bash
python3 --version                     # Python Version
pip3 install --user paket             # User-Installation

# Virtuelle Umgebungen
python3 -m venv venv                  # venv erstellen
source venv/bin/activate              # Aktivieren
```

### Typst

Modernes Textsatzsystem (LaTeX-Alternative).

```bash
typst compile dokument.typ            # PDF erstellen
typst watch dokument.typ              # Auto-Kompilierung
typst compile --format png slide.typ  # Als PNG

# Language Server: tinymist
# Automatisch in Neovim und VSCodium integriert
```

### Flutter/Dart

```bash
flutter doctor                        # System-Check
flutter create app_name               # Neue App
flutter run                           # App starten
flutter build apk                     # Android APK
flutter pub get                       # Dependencies installieren
```

### OpenBB (Investment Research)

FHS-Umgebung mit Python 3.11 und OpenBB 4.2.0.

```bash
openbb                                # OpenBB Terminal starten
obb                                   # Alias

# Erste Nutzung: Erstellt automatisch venv in ~/.local/share/openbb-venv
# Befehle im Terminal: /stocks, /crypto, /economy, etc.
```

---

## Dateimanagement

### yazi

Terminal-Dateimanager mit Vorschau.

```bash
yazi                                  # Starten
yazi /pfad                            # In bestimmtem Verzeichnis

# Tastenkürzel
# h,j,k,l - Navigation (Vim-style)
# Space   - Auswählen
# Enter   - Öffnen
# y       - Kopieren (yank)
# d       - Ausschneiden
# p       - Einfügen
# r       - Umbenennen
# /       - Suchen
# q       - Beenden
```

### fzf

Fuzzy Finder für interaktive Auswahl.

```bash
# Datei suchen und öffnen
vim $(fzf)                            # Datei mit vim öffnen

# History durchsuchen (Ctrl+R in Shell)
# Datei-Suche (Ctrl+T in Shell)

# Mit anderen Tools kombinieren
fd -t f | fzf                         # Alle Dateien fuzzy suchen
git log --oneline | fzf               # Commit auswählen
```

### zoxide

Intelligentes `cd` basierend auf Häufigkeit.

```bash
z projekt                             # Jump zu ~/Projekte/projekt
z doc                                 # Jump zu ~/Dokumente
zi                                    # Interaktive Auswahl (mit fzf)

# Lernt automatisch aus cd-Nutzung
# Je öfter du ein Verzeichnis besuchst, desto höher die Priorität
```

---

## Netzwerk & VPN

### ProtonVPN CLI

```bash
# Status
protonvpn-cli status                  # Verbindungsstatus
protonvpn-cli netshield               # NetShield Status

# Verbindung (via systemd beim Boot)
# Vorkonfiguriert in modules/protonvpn.nix

# Manuelle Steuerung
sudo systemctl status protonvpn       # Service-Status
sudo systemctl restart protonvpn      # Neu verbinden
```

### Curl & Wget

```bash
# curl (vorinstalliert)
curl -O https://example.com/file      # Download
curl -I https://example.com           # Headers
curl -X POST -d "key=value" url       # POST Request

# wget
wget https://example.com/file         # Download
wget -c url                           # Download fortsetzen
wget -r -np url                       # Rekursiv
```

---

## Sicherheit & Verschlüsselung

### Nitrokey (FIDO2 & GPG)

#### FIDO2 (libfido2)

```bash
# Token-Info
fido2-token -L                        # Geräte auflisten
fido2-token -I /dev/hidraw*           # Device-Info

# Credentials verwalten
fido2-cred -L /dev/hidraw*            # Credentials auflisten
```

#### pynitrokey

```bash
# Nitrokey 3 Status
nitropy nk3 status                    # Device-Status
nitropy nk3 list                      # Alle NK3 Geräte

# FIDO2
nitropy nk3 fido2 list-credentials    # Credentials
nitropy nk3 fido2 set-pin             # PIN ändern

# Secrets (TOTP)
nitropy nk3 secrets list              # TOTP-Einträge
nitropy nk3 secrets get-otp "name"    # TOTP-Code generieren

# Firmware
nitropy nk3 update                    # Firmware aktualisieren
nitropy nk3 version                   # Firmware-Version
```

#### TOTP Helper Script

```bash
totp-posteo                           # Posteo TOTP in Clipboard
# Automatisches Leeren nach 30s
# Benötigt Touch-Bestätigung am Nitrokey
```

### GPG

```bash
# Key-Verwaltung
gpg --list-keys                       # Öffentliche Schlüssel
gpg --list-secret-keys                # Private Schlüssel
gpg --export -a user@posteo.de # Public Key exportieren

# Verschlüsselung
gpg -e -r empfaenger@example.com file # Datei verschlüsseln
gpg -d file.gpg                       # Datei entschlüsseln

# Signierung
gpg --sign file                       # Signieren
gpg --verify file.sig                 # Signatur prüfen

# Mit Nitrokey
gpg --card-status                     # Smartcard-Status
```

### SSH

SSH-Keys mit FIDO2 (Nitrokey).

```bash
# FIDO2 Key generieren
ssh-keygen -t ed25519-sk              # Resident Key
ssh-keygen -t ed25519-sk -O resident  # Resident Key

# SSH-Agent (systemd user service)
ssh-add -l                            # Geladene Keys
ssh-add ~/.ssh/id_ed25519_sk          # Key hinzufügen

# Verbindungen (vorkonfiguriert)
ssh git@github.com                    # GitHub (Port 22)
ssh git@altssh.gitlab.com -p 443      # GitLab (Port 443)
```

---

## System Monitoring

### htop

Interaktiver Prozess-Viewer.

```bash
htop                                  # Starten

# Tastenkürzel
# F1  - Hilfe
# F2  - Setup
# F3  - Suchen
# F4  - Filter
# F5  - Baum-Ansicht
# F6  - Sortieren
# F9  - Kill
# F10 - Beenden
```

### bottom (`btm`)

Siehe [Modern Unix Tools](#bottom-btm).

### System Tools

```bash
# Festplattenbelegung
df -h                                 # Partitionen
dust                                  # Visualisiert (Alias: du)
baobab                                # GNOME GUI (Disk Usage Analyzer)

# Prozesse
ps aux | grep prozess                 # Prozess suchen
pgrep -a prozess                      # Prozess-IDs
pkill prozess                         # Prozess beenden

# Logs
journalctl -xe                        # Systemd-Logs
journalctl -f                         # Logs live
journalctl -u servicename             # Bestimmter Service

# Netzwerk
ip addr                               # IP-Adressen
ip route                              # Routing-Tabelle
ss -tulpn                             # Offene Ports
```

---

## Editor: Neovim

Vorkonfiguriert mit Rust-IDE-Features und AI-Assistenz.

### Starten

```bash
nvim datei.txt                        # Datei öffnen
vim datei.txt                         # Alias
vi datei.txt                          # Alias
```

### Basis-Tastenkürzel (Vim)

```
# Modi
i       - Insert Mode
Esc     - Normal Mode
v       - Visual Mode
:       - Command Mode

# Navigation
h,j,k,l - Links, Runter, Hoch, Rechts
w       - Nächstes Wort
b       - Vorheriges Wort
gg      - Datei-Anfang
G       - Datei-Ende
0       - Zeilen-Anfang
$       - Zeilen-Ende

# Editieren
dd      - Zeile löschen
yy      - Zeile kopieren
p       - Einfügen
u       - Undo
Ctrl+r  - Redo

# Speichern/Beenden
:w      - Speichern
:q      - Beenden
:wq     - Speichern & Beenden
:q!     - Beenden ohne Speichern
```

### Vorkonfigurierte Keybindings

**Leader-Key:** `Space`

#### LSP (Language Server)

```
gd          - Go to Definition
K           - Hover Documentation
<leader>ca  - Code Actions
<leader>rn  - Rename Symbol
gr          - Find References
<leader>f   - Format Document
```

#### Telescope (Fuzzy Finder)

```
<leader>ff  - Find Files
<leader>fg  - Live Grep (Text suchen)
<leader>fb  - Find Buffers
```

#### Debug Adapter (nvim-dap)

```
F5          - Continue/Start Debugging
F10         - Step Over
F11         - Step Into
F12         - Step Out
<leader>b   - Toggle Breakpoint
<leader>B   - Conditional Breakpoint
<leader>du  - Toggle Debug UI
```

#### Avante.nvim (AI-Assistenz)

```
<leader>aa  - Ask AI
<leader>ae  - Edit with AI
<leader>ar  - Refresh AI
<leader>at  - Toggle AI Window
<leader>ad  - Toggle Debug
<leader>ah  - Toggle Hints
```

#### Octo.nvim (GitHub Integration)

```
<leader>oi  - List Issues
<leader>op  - List Pull Requests
<leader>or  - Start Code Review
```

### Plugins

**Wichtigste Plugins:**

- **rustaceanvim** - Rust IDE Features (auto-konfiguriert)
- **nvim-cmp** - Autocompletion
- **crates.nvim** - Cargo.toml Dependency-Management
- **telescope.nvim** - Fuzzy Finder
- **nvim-dap** - Debugging mit codelldb
- **avante.nvim** - Claude AI-Assistenz (Cursor-ähnlich)
- **octo.nvim** - GitHub Integration (Issues, PRs, Reviews)
- **catppuccin** - Farbschema (Mocha)

### Rust-spezifische Features

```
# Automatisch beim Öffnen von .rs Dateien:
- rust-analyzer LSP
- Clippy als Check-Command
- Cargo.toml Dependency-Autocomplete
- Code Actions (Auto-Import, etc.)
- Debugging mit codelldb

# In Cargo.toml:
- Crate-Versionen werden angezeigt
- Autocomplete für Dependencies
- Update-Benachrichtigungen
```

---

## Nix Package Management

### nixos-rebuild

```bash
# System aktualisieren
nrs                                   # Alias (vorkonfiguriert)
sudo nixos-rebuild switch --flake \
  /home/user/nixos-config#nixos

# Andere Modi
sudo nixos-rebuild boot --flake .    # Beim nächsten Boot
sudo nixos-rebuild test --flake .    # Temporär (ohne Boot)
sudo nixos-rebuild dry-run --flake . # Simulation
```

### Flake-Management

```bash
# Updates
cd ~/nixos-config
nix flake update                      # Alle Inputs aktualisieren
nix flake update nixpkgs              # Nur nixpkgs
nix flake lock                        # Lock-File neu generieren

# Info
nix flake show                        # Flake-Outputs anzeigen
nix flake metadata                    # Flake-Metadaten
```

### Nix-Shell & Development

```bash
# Temporäre Pakete
nix shell nixpkgs#paket               # Paket temporär nutzen
nix shell nixpkgs#python3 nixpkgs#git # Mehrere Pakete

# Development Shell
nix develop                           # devShell aus flake.nix
nix develop -c bash                   # Mit bash statt $SHELL

# Direnv (automatisch)
# .envrc mit: use flake
# Aktiviert automatisch beim cd ins Verzeichnis
```

### Garbage Collection

```bash
# Automatisch: wöchentlich (>30 Tage alt)
# Manuelle Garbage Collection
nix-collect-garbage -d               # Alte Generationen löschen
nix-store --gc                       # Store aufräumen
nix-store --optimise                 # Deduplizierung
```

### Home Manager

```bash
# Home Manager aktualisieren (inkludiert in nixos-rebuild)
home-manager switch --flake ~/nixos-config

# Generationen verwalten
home-manager generations             # Generationen auflisten
home-manager remove-generations 30d  # >30 Tage alt löschen
```

---

## Sonstiges

### AI Coding Tools

#### aider

AI Pair Programming.

```bash
aider                                 # Starten (nutzt ANTHROPIC_API_KEY)
aider file1.rs file2.rs               # Bestimmte Dateien
aider --model claude-sonnet-4         # Modell wählen

# Im aider-Prompt:
# /add file.rs  - Datei hinzufügen
# /drop file.rs - Datei entfernen
# /help         - Hilfe
# /quit         - Beenden
```

#### crush

LLM-basiertes CLI-Tool.

```bash
crush "erkläre mir diesen Code"
crush "schreibe einen Test für diese Funktion"
```

### Systemd Services

```bash
# Service-Status
systemctl status servicename          # System-Service
systemctl --user status servicename   # User-Service

# Service-Kontrolle (benötigt sudo für System)
sudo systemctl start servicename
sudo systemctl stop servicename
sudo systemctl restart servicename
sudo systemctl enable servicename     # Autostart

# User Services (kein sudo)
systemctl --user start ssh-agent
systemctl --user status posteo-keyring-sync

# Logs
journalctl -u servicename             # Service-Logs
journalctl -u servicename -f          # Live-Logs
journalctl --user -u servicename      # User-Service Logs
```

### Screenshot & Clipboard (Wayland)

```bash
# Screenshot
grim screenshot.png                   # Gesamter Bildschirm
grim -g "$(slurp)" screenshot.png     # Bereich auswählen
grim - | swappy -f -                  # Mit Annotation

# Clipboard
wl-copy < file.txt                    # In Clipboard kopieren
wl-paste > file.txt                   # Aus Clipboard einfügen
wl-paste --type text/uri-list         # Dateipfade
```

### Sops (Secrets Management)

```bash
# Secrets editieren (benötigt Age-Key)
sops ~/nixos-config/secrets/secrets.yaml

# Secret in Klartext lesen (Debug)
sudo cat /run/secrets/anthropic-api-key

# Secrets werden automatisch geladen beim Boot
# Verfügbar in: /run/secrets/*
```

### TLP (Power Management)

```bash
# Status
sudo tlp-stat                         # Vollständiger Status
sudo tlp-stat -b                      # Nur Akku

# Lademodus
charge                                # Alias: sudo tlp fullcharge
sudo tlp setcharge 75 80              # Ladegrenzen setzen
sudo tlp start                        # TLP starten
```

### Resume Builder

```bash
# Resumed - JSON Resume Builder
resumed init                          # Neue resume.json erstellen
resumed export resume.json resume.pdf # PDF exportieren
resumed validate resume.json          # Validieren
```

---

## Tastenkürzel-Übersicht

### Globale Shell-Shortcuts (Nushell + Carapace)

```
Ctrl+R    - History-Suche (fuzzy mit fzf)
Ctrl+T    - Datei-Suche mit fzf
Tab       - Autocomplete (Carapace)
Ctrl+C    - Abbrechen
Ctrl+D    - Beenden
Ctrl+L    - Terminal löschen
```

### Git-UI (gitui)

```
1-5       - Tabs wechseln
c         - Commit
s         - Stage/Unstage
e         - Edit
P         - Push
p         - Pull
q         - Beenden
```

### Bottom (btm)

```
/         - Suchen
dd        - Prozess killen
t         - Baum-Ansicht
c,m,p     - CPU/RAM/Prozess
q         - Beenden
```

---

## Schnellreferenz nach Aufgabe

### "Ich will..."

**...eine Datei finden:**
```bash
fd dateiname                          # Dateiname
fd -e rs                              # Nach Endung
fzf                                   # Interaktiv
```

**...Text in Dateien suchen:**
```bash
rg "pattern"                          # Schnell
rg -t rust "fn main"                  # In Rust-Dateien
```

**...Festplattenbelegung sehen:**
```bash
dust                                  # Visualisiert
dust -d 3                             # Max Tiefe 3
df -h                                 # Partitionen
```

**...Prozesse überwachen:**
```bash
btm                                   # Modern (bottom)
htop                                  # Klassisch
```

**...mit Git arbeiten:**
```bash
gitui                                 # Terminal-UI
gs                                    # git status (Alias)
gh pr list                            # GitHub PRs
```

**...Code bearbeiten:**
```bash
nvim datei.rs                         # Neovim (Rust-IDE)
vim datei.txt                         # Vim
code .                                # VSCodium
```

**...ein Paket temporär nutzen:**
```bash
nix shell nixpkgs#paket
nix run nixpkgs#paket
```

**...das System aktualisieren:**
```bash
nrs                                   # nixos-rebuild switch
```

**...einen TOTP-Code holen:**
```bash
totp-posteo                           # Nitrokey → Clipboard
```

---

## Konfigurationsdateien

### Wichtige Pfade

```
~/nixos-config/                       # NixOS Config (Flake)
~/.config/nushell/                    # Nushell Config
~/.config/nvim/                       # Neovim (via Home Manager)
~/.config/starship.toml               # Prompt
~/.ssh/                               # SSH-Keys
~/.gnupg/                             # GPG-Keys
~/.config/sops/age/keys.txt           # Sops Age-Key
~/.npm-global/                        # Global npm packages
/run/secrets/                         # Sops-Secrets (Runtime)
```

### Umgebungsvariablen

```bash
# In Nushell verfügbar
$env.EDITOR                           # vim
$env.ANTHROPIC_API_KEY                # Aus /run/secrets/
$env.GH_TOKEN                         # Aus /run/secrets/
$env.SSH_AUTH_SOCK                    # SSH-Agent
$env.SOPS_AGE_KEY_FILE                # Sops Key
$env.NPM_CONFIG_PREFIX                # npm global prefix
```

---

## Nützliche Links

- **Nushell:** https://www.nushell.sh/
- **Neovim:** https://neovim.io/
- **NixOS:** https://nixos.org/
- **Home Manager:** https://github.com/nix-community/home-manager
- **Nitrokey:** https://docs.nitrokey.com/

---

**Erstellt:** 2026-02-03
**System:** nixos (NixOS 24.11)
**Shell:** Nushell mit Starship, Carapace, Direnv, Zoxide
