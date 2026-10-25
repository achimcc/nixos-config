---
name: speicherplatz-freigeben
description: Findet und gibt Speicherplatz auf der Workstation frei — Nix-Store und GC-Wurzeln, Rust-target/-Verzeichnisse, cargo/npm/pip-Caches, Browser- und Anwendungs-Caches, Flatpak, Journal, /tmp, verwaiste Worktrees. Benutze diesen Skill immer, wenn die Platte voll läuft oder voll ist, `df` hohe Prozente zeigt, ein Bau mit „No space left on device" scheitert, der Nix-Daemon „deleting unused links" hängt, oder der Nutzer fragt, wo Platz draufgeht, was er löschen kann, ob ein GC hilft oder wie groß ein Cache ist — auch wenn er nur „aufräumen", „Festplatte", „Speicher frei machen" oder „was frisst Platz" sagt.
---

# Speicherplatz freigeben

Die Workstation hat EIN ext4-Dateisystem (442 GB, LUKS) für `/` und `/nix/store`. Was im
Home wächst, nimmt dem Store den Platz und umgekehrt. Der Nix-Daemon räumt selbst auf, sobald
unter 20 GiB frei sind (`min-free`/`max-free` in `configuration.nix`) — fällt `df` darunter,
ist ein Bau oft schon blockiert.

Vorgehen in drei Schritten: **messen → Liste mit Kategorien vorlegen → nur das Freigegebene
löschen, danach erneut messen.** Löschen ist hier fast immer irreversibel, und auf der
Maschine laufen oft ein Dutzend paralleler Sitzungen, deren Bauten genau in den Verzeichnissen
liegen, die am größten aussehen.

## 1. Messen

Zuerst `lotse status` — wer baut, wertet aus, deployt, in welchem Worktree. Ein `target/`
oder `CARGO_TARGET_DIR`, das dort auftaucht, ist tabu, solange der Lauf lebt.

Dann das Bestandsskript (nur lesend, mit Zeitgrenzen je Messung):

```bash
bash <skill-dir>/scripts/bestandsaufnahme.sh > <scratchpad>/bestand.txt 2>&1
```

Es braucht unter Last mehrere Minuten: mit `run_in_background` starten und auf die
Benachrichtigung warten. `du -xs /nix/store` lässt es absichtlich weg (dauert >5 min) — die
Store-Größe ergibt sich aus `df` minus Home minus `/tmp`/`/var`.

Was das Skript nicht abdeckt, gezielt mit `du -xsh <pfad>` nachmessen, nie
`du` über `/` ohne `-x` und Zeitgrenze.

## 2. Kategorien und was sie freigeben

Messwerte vom 2026-10-25 als Größenordnung (94 % belegt, 28 GB frei); die echten Zahlen
liefert jedes Mal die Messung.

### A — gefahrlos, sofort wieder erzeugbar (als Nutzer)

| Was | Typisch | Befehl |
|-----|---------|--------|
| Rust-`target/` in `~/Projects` | **~63 GB**, 60 Stück | `cargo clean` im Projekt, oder `rm -rf <proj>/target` |
| `~/.npm/_cacache` | 2,4 GB | `npm cache clean --force` |
| `~/.cargo/registry/cache`, `~/.cargo/git/db` | 2,6 GB | löschen; cargo lädt nach (`registry/src` ist entpackt, ebenfalls ersetzbar) |
| `~/.cache/pip`, `~/.cache/uv` | 0,4 GB | `pip cache purge`, `uv cache clean` |
| `~/.cache/trivy`, `~/.cache/vulnix` | 2 GB | löschen; nächster Scan lädt die DB neu |
| Browser-/App-Caches: `~/.cache/google-chrome`, `spotify`, `gnome-software`, `epiphany`, `thumbnails`, `mesa_shader_cache` | 3 GB | löschen, während die Anwendung geschlossen ist |
| `~/.local/share/Trash` | klein | leeren |

Bei `target/`: zuerst die größten, und nur solche, deren Projekt gerade kein Lauf in
`lotse status` benutzt. Ein `target/` mit Release-Bauten kostet beim nächsten Bau Minuten bis
Stunden — bei aktiv bearbeiteten Projekten lieber `cargo sweep`-artig nur alte Profile
(`target/debug/incremental`, `target/*/deps` älter als X) als alles.

### B — Nix (Kern des Problems)

Der Store ist mit ~250 GB der größte Posten. Er schrumpft nur, wenn **GC-Wurzeln** wegfallen;
ein `nix-collect-garbage` ohne vorheriges Abräumen der Wurzeln bringt wenig.

1. **Wurzeln zählen und zuordnen:**
   `nix-store --gc --print-roots | grep -v '^/proc'`, nach Verzeichnis gruppieren. Am
   2026-10-25 kamen 481 von 618 Wurzeln aus `~/Projects/homeserver-worktrees` — je Worktree
   ~61 aus `.direnv/` (nix-direnv: `flake-profile-*` und `flake-inputs/*`) plus
   `.gcroots/node-server`. 63 Worktrees halten so je eine komplette Entwicklungs-Umgebung und
   ihre Flake-Inputs fest.
2. **Verwaiste Worktrees** sind der größte Hebel. Ein Worktree ist abräumbar, wenn sein Zweig
   in `main` gemergt ist (`git -C ~/Projects/homeserver branch --merged main`), er nicht in
   `lotse status` steht und `git -C <wt> status --short` leer ist. Abräumen mit
   `git -C ~/Projects/homeserver worktree remove <pfad>` — das nimmt `.direnv`, `.gcroots`
   und `target/` mit. Ungemergte oder schmutzige Worktrees nur nach Rückfrage, sie sind
   oft die laufende Arbeit einer anderen Sitzung.
3. **`result`-Links und Wurzeln in `/tmp`** (`/tmp/t23/system`, alte Scratchpads unter
   `/tmp/claude-1000/*/scratchpad/`): Probebauten anderer Sitzungen. Alte (> 1 Tag) und
   nicht in `lotse status` → Link löschen. `/tmp` lag bei 13 GB.
4. **Dann sammeln — als Nutzer:** `nix-store --gc` (ohne `-d`) löscht nur Unerreichbares und
   braucht kein root. Was er freigäbe, zeigt vorher `nix-store --gc --print-dead` (Zählen ist
   billig, `du` über die toten Pfade dauert lange).
5. **Generationen** sind schon knapp: 5 System-, 5 Home-Manager-Generationen, `nix.gc`
   wöchentlich mit `--delete-older-than 30d`. Alte Systemgenerationen zu löschen braucht
   root und damit den FIDO2-Stick — das macht der Nutzer selbst (Befehl unten). Die laufende
   und die Boot-Generation bleiben immer.
6. `~/.cache/nix` (2,3 GB: Eval-Cache, Tarballs der Flake-Inputs) ist löschbar, die nächste
   Auswertung dauert dann länger. `~/.local/share/nix/root` (9 GB) ist ein **Chroot-Store**
   eines Nix-Laufs ohne Zugriff auf `/nix` — erst klären, welches Werkzeug ihn angelegt hat
   (Datum, Inhalt von `root/nix/store`), dann löschen.

`auto-optimise-store = true` ist an: Hardlinks machen `du`-Summen über Store-Pfade größer als
den echten Gewinn. Den Gewinn misst nur `df` vorher/nachher.

### C — nur auf Rückfrage

- `~/.local/share/flatpak` (5,6 GB): `flatpak uninstall --unused` ist harmlos; ganze Apps nur,
  wenn der Nutzer sie nicht mehr braucht.
- Journal (1,9 GB) und `/var/log`: braucht root. Dauerhaft deklarativ über
  `services.journald.extraConfig = "SystemMaxUse=500M";` statt `--vacuum-size` von Hand.
- `~/.claude/projects` (1,2 GB): Sitzungsprotokolle. **`memory/`-Unterordner nie anfassen** —
  das ist das Gedächtnis. Alte `*.jsonl` (> 30 Tage) nur nach Rückfrage.
- `~/.npm-global` (3,7 GB): installierte Werkzeuge, kein Cache.
- `~/.local/share/openbb-venv` (1,6 GB), `~/.config/discord` (1,3 GB), alte
  `*.backup-*`-Ordner in `~/.config`: fragen.

### D — nicht anfassen

- `~/.local/share/xmr-btc-swap`, `eigenwallet`, `net.unstoppableswap.gui`: Wallet- und
  Swap-Zustand. Löschen kann Geld kosten.
- `~/.thunderbird`, `~/Dokumente`, `Camera*`, `Signal-Backup-*`, `~/.local/share/shadow`:
  Nutzerdaten.
- `~/Projects/proxmox`: Archiv, Änderungen nur auf ausdrückliche Bitte.
- `~/Depot`: Netzlaufwerk (sshfs), zählt nicht zur lokalen Platte — `du -x` lässt es aus.
- `/nix/store` direkt: nie `rm`, nur über `nix-store --gc`.

## 3. Vorlegen, löschen, nachmessen

Bericht an den Nutzer — eine Tabelle, nach Gewinn sortiert:

```
| Kat. | Was                        | Größe  | Befehl / Vorgehen            |
|------|----------------------------|--------|------------------------------|
| A    | target/ in 23 Projekten    | 58 GB  | cargo clean je Projekt       |
| B    | 31 gemergte Worktrees      | ~40 GB | git worktree remove + GC     |
| ...                                                                        |
Summe A: … GB sofort, B: … GB nach GC (Schätzung), C: … GB auf Rückfrage
```

Kategorie A darf direkt ausgeführt werden, wenn der Nutzer „räum auf" gesagt hat; B (Worktrees),
C und alles mit root erst nach seinem Ja zur konkreten Liste. Läuft parallel schon eine andere
Aufräum-Sitzung (`lotse status`, frische Löschungen), nichts doppelt anfassen — nur messen.

Danach `df -h /` erneut und die Differenz melden — nicht die Summe der `du`-Werte, die lügt bei
Hardlinks und bei gleichzeitig wachsenden Bauten.

## Befehle für den Nutzer (Nushell)

Seine Shell ist `nu`: kein `&&`, kein `$(…)`. Root-Schritte, die er selbst startet:

```nu
# Alte Systemgenerationen (älter als 14 Tage) löschen und sammeln
sudo nix-collect-garbage --delete-older-than 14d

# Journal begrenzen (einmalig; dauerhaft besser deklarativ)
sudo journalctl --vacuum-size=500M

# Mehrere Schritte, Abbruch beim ersten Fehler
try { npm cache clean --force; nix-store --gc } catch { print "Abbruch" }
```

Nie `nixos-rebuild` oder einen Systembau anstoßen, um „Platz zu prüfen" — siehe `CLAUDE.md`
des nixos-config-Repos.
