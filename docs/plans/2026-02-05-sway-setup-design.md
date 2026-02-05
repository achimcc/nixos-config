# Sway Setup Design für User "user"

**Datum**: 2026-02-05
**Status**: Approved
**Typ**: Feature Implementation

## Übersicht

Minimales, funktionales Sway-Setup als alternative Window Manager Session neben GNOME. User "user" kann bei GDM zwischen GNOME und Sway wählen.

## Ziele

- Alternative Wayland-Session mit Tiling Window Manager
- Minimale Starter-Konfiguration (erweiterbar)
- Keine Konflikte mit bestehendem GNOME-Setup
- Essentielle Tools: waybar, mako, kanshi, grim

## Architektur

### Module-Struktur

```
nixos-config/
├── modules/home/
│   └── sway.nix          # Neues Modul für Sway + Komponenten
└── home.nix        # Import des Sway-Moduls
```

### Komponenten

| Komponente | Zweck | Autostart |
|------------|-------|-----------|
| **Sway** | Tiling Window Manager (Wayland) | - |
| **Waybar** | Status-Bar (workspaces, system info) | Ja |
| **Mako** | Notification Daemon | Ja (nur in Sway) |
| **Kanshi** | Monitor-Management | Ja (systemd user service) |
| **Grim** | Screenshot Tool | Nein (via Keybinding) |
| **Slurp** | Bereichsauswahl für Screenshots | Nein (bereits installiert) |
| **Swappy** | Screenshot-Annotation | Nein (bereits installiert) |
| **Wofi** | Application Launcher | Nein (via `$mod+d`) |

### Session-Management

- **GDM**: Zeigt beide Sessions (GNOME + Sway)
- **Home-Verzeichnis**: Geteilt zwischen beiden Sessions
- **Konfiguration**: Deklarativ via Home Manager
- **Konflikte vermeiden**: mako startet nur in Sway (nicht in GNOME)

## Sway Konfiguration

### Keybindings (Minimal)

| Keybinding | Aktion |
|------------|--------|
| `$mod` | Super/Windows-Taste (Mod4) |
| `$mod+Return` | Terminal (Blackbox) |
| `$mod+d` | Application Launcher (wofi) |
| `$mod+Shift+q` | Fenster schließen |
| `$mod+Shift+c` | Sway neu laden |
| `$mod+Shift+e` | Sway beenden (mit Bestätigung) |
| `$mod+1..9` | Workspace wechseln |
| `$mod+Shift+1..9` | Fenster zu Workspace verschieben |
| `$mod+h/j/k/l` | Fokus bewegen (alternativ: Pfeiltasten) |
| `$mod+Shift+Space` | Floating toggle |
| `Print` | Screenshot (Vollbild) |
| `Shift+Print` | Screenshot (Bereich mit slurp) |

### Window Management

- **Layout**: Standard Sway Tiling (horizontal/vertical splits)
- **Floating**: Aktivierbar via `$mod+Shift+Space`
- **Workspaces**: 1-9 auf primary output
- **Focus**: Folgt Maus (optional: focus_follows_mouse no)

### Autostart

```bash
exec waybar
exec mako
exec kanshi
```

## Waybar Konfiguration

### Layout

```
┌────────────────────────────────────────────────────────────┐
│ [1][2][3]...     Window Title              🔊 📶 🔋 🕐    │
└────────────────────────────────────────────────────────────┘
```

### Module (Links → Rechts)

1. **Workspaces**: Klickbar, highlight aktiver workspace
2. **Window Title**: Aktuelles Fenster (zentriert)
3. **Tray**: System-Tray Icons
4. **PulseAudio**: Lautstärke, klickbar → pavucontrol
5. **Network**: WLAN/LAN Status, klickbar → nmtui
6. **Battery**: Prozent + Icon
7. **Clock**: Uhrzeit (HH:MM)

### Styling

- **Position**: Top
- **Theme**: Dunkel (passend zu Sway-Defaults)
- **Höhe**: 30px
- **Font**: System-Default

## Mako Konfiguration

### Notification Settings

- **Position**: Top-Right
- **Timeout**:
  - Normal: 5 Sekunden
  - Kritisch: 0 (permanent, manuell schließen)
- **Max Notifications**: 5 sichtbar
- **Actions**: Klick schließt Notification

### Styling

- **Background**: Dunkel (#2e3440 oder ähnlich)
- **Border**: Runde Ecken (radius: 5px)
- **Font**: System-Default
- **Padding**: 10px

### Sway-Integration

Startet nur in Sway-Session (Bedingung: `$XDG_CURRENT_DESKTOP == "sway"`).

## Kanshi Konfiguration

### Profile

**Fallback-Profil** (generisch):
```
profile default {
  output * enable
}
```

- Aktiviert alle erkannten Displays automatisch
- Hot-Plug Support (erkennt Monitor-Änderungen)
- Läuft als systemd user service

### Zukünftige Erweiterungen

User kann später spezifische Profile hinzufügen:
```
profile laptop {
  output eDP-1 enable scale 1.0
}

profile docked {
  output eDP-1 disable
  output HDMI-A-1 enable scale 1.0
}
```

## Screenshot-Workflow

### Vollbild-Screenshot

```bash
# Keybinding: Print
grim ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png
```

### Bereichs-Screenshot

```bash
# Keybinding: Shift+Print
grim -g "$(slurp)" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png
```

### Mit Annotation (manuell)

```bash
grim -g "$(slurp)" - | swappy -f -
```

## Implementierungs-Details

### Dateistruktur

```
modules/home/sway.nix
├── wayland.windowManager.sway.enable = true
├── wayland.windowManager.sway.config = { ... }
├── programs.waybar = { ... }
├── services.mako = { ... }
├── services.kanshi = { ... }
└── home.packages = [ wofi ]
```

### Home Manager Integration

```nix
# home.nix
imports = [
  ./modules/home/gnome-settings.nix
  ./modules/home/neovim.nix
  ./modules/home/sway.nix  # NEU
];
```

### Shared Resources

Folgende bereits installierte Pakete werden genutzt:
- grim (Screenshot)
- slurp (Bereichsauswahl)
- swappy (Screenshot-Annotation)
- wl-clipboard (Clipboard)
- blackbox-terminal (Terminal)
- wezterm (Alternative Terminal)

## Konflikte & Vermeidung

### GNOME vs. Sway

| Service | GNOME | Sway | Lösung |
|---------|-------|------|--------|
| Notifications | gnome-shell | mako | mako nur in Sway starten |
| Display Manager | GDM | GDM | Teilen (zeigt beide Sessions) |
| Clipboard | GNOME-Shell | wl-clipboard | Beide kompatibel |
| Screen Lock | GDM Lock | swaylock | Sway nutzt swaylock (nicht Teil dieser minimalen Config) |

### Systemd User Services

Kanshi läuft als systemd user service mit:
```
WantedBy = graphical-session.target
```

Dies verhindert, dass es in GNOME startet (da GNOME eigenes Monitor-Management hat).

## Testing-Plan

Nach Implementierung testen:

1. **Build**: `nixos-rebuild build --flake .#nixos`
2. **Switch**: `nixos-rebuild switch --flake .#nixos`
3. **Logout** und bei GDM "Sway" Session wählen
4. **Verifizieren**:
   - [ ] Sway startet
   - [ ] Waybar wird angezeigt
   - [ ] `$mod+Return` öffnet Terminal
   - [ ] `$mod+d` öffnet wofi
   - [ ] Screenshot mit `Print` funktioniert
   - [ ] Notifications via `notify-send "Test"` erscheinen
   - [ ] Workspace-Wechsel mit `$mod+1..9`
5. **GNOME testen**: Logout, GNOME wählen, verifizieren dass alles funktioniert

## Zukünftige Erweiterungen

Diese minimale Config ist erweiterbar um:
- swaylock (Screen Locker)
- swayidle (Auto-Lock/Suspend)
- Spezifische kanshi-Profile für Monitor-Setups
- Custom Sway-Themes
- Weitere Keybindings
- Scratchpad-Configuration
- Multi-Monitor-optimierte Workspace-Assignments

## Referenzen

- [Sway Wiki](https://github.com/swaywm/sway/wiki)
- [Waybar Configuration](https://github.com/Alexays/Waybar/wiki)
- [Home Manager Sway Options](https://nix-community.github.io/home-manager/options.xhtml#opt-wayland.windowManager.sway.enable)
