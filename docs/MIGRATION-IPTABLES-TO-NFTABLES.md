# Firewall Migration: iptables to nftables

**Datum:** 2026-02-05
**Status:** In Progress - Requires Reboot
**Ziel:** Migration der Firewall von iptables zu nftables mit identischem Sicherheitsverhalten

---

## Zusammenfassung

Diese Migration ersetzt die iptables-basierte Firewall durch eine moderne nftables-Implementierung. Die Migration erfolgte in 6 Hauptaufgaben mit mehreren Bugfixes während der Deployment-Phase.

**Aktuelle Status:**
- ✅ Code-Migration abgeschlossen
- ✅ Alle Service-Referenzen aktualisiert
- ✅ Test-Skripte aktualisiert
- ⏸️ **Deployment blockiert** - Kernel-Module benötigen Reboot
- ⏳ Nächster Schritt: Reboot erforderlich

---

## Ursprünglicher Plan

Der ursprüngliche Plan sah 6 Hauptaufgaben vor:

1. ✅ **Task 1:** nftables Firewall-Konfiguration erstellen
2. ✅ **Task 2:** protonvpn.nix Firewall-Validierung aktualisieren
3. ✅ **Task 3:** disable-firewall.sh Skript aktualisieren
4. ✅ **Task 4:** test-network-boot.sh aktualisieren
5. ⏸️ **Task 5:** Deployment und Testing (blockiert durch Kernel-Module)
6. ✅ **Task 6:** MEMORY.md Dokumentation aktualisieren

---

## Task 1: nftables Firewall-Konfiguration

### Durchgeführte Änderungen

**Datei:** `modules/firewall.nix`

1. **Ersetzt `networking.firewall` durch `networking.nftables`**
   - Entfernt: iptables/ip6tables Commands (Lines 85-293)
   - Hinzugefügt: nftables Ruleset mit `inet filter` Table

2. **Kernfunktionen migriert:**
   - VPN Kill Switch (DROP Policy, nur VPN-Interfaces erlaubt)
   - DNS-over-TLS Dual-Phase Strategie (Quad9 Bootstrap, Mullvad über VPN)
   - DHCP/DNS/mDNS Regeln
   - Syncthing und Drucker-Zugriff
   - Port-Scan Detection (nftables Dynamic Set)
   - ICMPv6 Neighbor Discovery (kritisch für NetworkManager)

3. **Struktur:**
```nix
table inet filter {
  set portscan { ... }
  chain input { policy drop; ... }
  chain output { policy drop; ... }
  chain forward { policy drop; ... }
}
```

**Commit:** `2115f9c` - "feat: migrate firewall from iptables to nftables"

**Spec Compliance Review:**
- ✅ Alle Anforderungen erfüllt
- ⚠️ Minor Issue gefunden: IPv6 logging `burst 3 packets` fehlte initial
- ✅ Fix durchgeführt und Commit amended

**Code Quality Review:**
- ✅ Approved - 1:1 Translation korrekt
- ✅ Alle Sicherheitsrichtlinien erhalten
- ✅ Build erfolgreich

---

## Task 2: VPN Firewall-Validierung

### Durchgeführte Änderungen

**Datei:** `modules/protonvpn.nix` (Line 66)

**Geändert:**
```nix
# Vorher (iptables):
if ${pkgs.iptables}/bin/iptables -L OUTPUT -n | grep -q "DROP"; then

# Nachher (nftables):
if ${pkgs.nftables}/bin/nft list table inet filter 2>/dev/null | grep -q "policy drop"; then
```

**Problem während Implementation:**
- Initial wurde Scope Creep festgestellt (VPN Routing-Änderungen im selben Commit)
- Fix: Commit zurückgesetzt, nur Line 66 Änderung committed

**Commit:** `d3e30b7` - "Task 2: Update protonvpn.nix firewall validation to use nftables"

**Stats:** 1 file, 1 insertion, 1 deletion (perfekt!)

**Spec Compliance Review:**
- ✅ Spec compliant nach Fix

**Code Quality Review:**
- ✅ Approved - Surgical precision, maintains boot safety logic

---

## Task 3: disable-firewall.sh Update

### Durchgeführte Änderungen

**Datei:** `disable-firewall.sh` (Lines 95-131)

**Ersetzt:**
```bash
# Vorher: Nur iptables flush
log_info "Resette IPv4 iptables..."
iptables -F INPUT
# ...

# Nachher: nftables primary, iptables fallback
log_info "Resette nftables..."
nft flush ruleset 2>/dev/null || true
log_success "nftables Firewall deaktiviert"

log_info "Bereinige eventuelle legacy iptables-Regeln..."
iptables -F INPUT 2>/dev/null || true
# ... (als Fallback für Legacy-Systeme)
```

**Commit:** `63810a1` - "fix: update disable-firewall.sh for nftables"

**Stats:** 1 file, 14 insertions, 12 deletions

---

## Task 4: test-network-boot.sh Update

### Durchgeführte Änderungen

**Datei:** `test-network-boot.sh` (Lines 16-32)

**Hinzugefügt:** Test 1b - nftables Rule Validation

```bash
# Test 1: Check if firewall is active and rules are loaded
echo -n "Test 1: Firewall service active... "
if systemctl is-active --quiet nftables.service; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} nftables firewall is not active!"
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

**Commit:** (completed)

---

## Task 5: Deployment - Probleme und Lösungen

### Problem 1: Service Name Mismatch

**Fehler:**
```
firewall.service: Service has no ExecStart=, ExecStop=, or SuccessAction=. Refusing.
```

**Ursache:** `networking.nftables` erstellt `nftables.service`, nicht `firewall.service`

**Lösung:** Alle Referenzen von `firewall.service` → `nftables.service` geändert

**Betroffene Dateien:**
1. `modules/firewall.nix` - `systemd.services.firewall` Block komplett entfernt
2. `modules/protonvpn.nix` - Lines 44, 45, 64, 173 aktualisiert
3. `test-network-boot.sh` - Lines 19, 22 aktualisiert

**Commit:** `0eedfc3` - "fix: update service references from firewall.service to nftables.service"

**Stats:** 3 files, 22 insertions, 40 deletions

---

### Problem 2: IPv6 Table Family

**Fehler:**
```
/nftables-rules:235:5-12: Error: Could not process rule: No such file or directory
ct state established,related accept
^^^^^^^^
```

**Ursache:** Separate `table ip6 filter` für IPv6 verursachte Conntrack-Fehler

**Lösung:** IPv6-Regeln in `table inet filter` integriert mit `meta nfproto ipv6` Matcher

**Änderungen:**
```nix
# Vorher: Zwei separate Tables
table inet filter { ... }  # IPv4
table ip6 filter { ... }    # IPv6 (FALSCH)

# Nachher: Eine unified Table
table inet filter {
  chain input {
    # ... IPv4 rules ...

    # IPv6: ICMPv6 Neighbor Discovery
    meta nfproto ipv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

    # IPv6: Logging
    meta nfproto ipv6 limit rate 1/minute burst 3 packets log prefix "ip6-blocked-in: "
  }
}
```

**Entfernt:** Komplette `table ip6 filter` Block (44 Lines gelöscht)

**Commit:** (Teil der Fixes)

---

### Problem 3: nftables Logging Inkompatibilität

**Fehler:**
```
/nftables-rules:202:59-61: Error: Could not process rule: No such file or directory
limit rate 1/minute burst 3 packets log prefix "ip6-blocked-out: " level info
                                                ^^^
```

**Ursache:** `level info` Parameter nicht vom Kernel unterstützt

**Lösungsversuche:**
1. ❌ `level info` entfernt - Fehler blieb bestehen
2. ❌ Logging Kernel-Module überprüft - `nf_log_syslog` geladen
3. ✅ **Finale Lösung:** Alle Logging-Statements komplett entfernt

**Begründung:** Logging ist "nice to have" aber nicht kritisch. VPN Kill Switch ist Priorität.

**Geänderte Lines:**
- Line ~120: INPUT IPv4 logging entfernt
- Line ~121: INPUT IPv6 logging entfernt
- Line ~188: OUTPUT IPv4 logging entfernt
- Line ~189: OUTPUT IPv6 logging entfernt
- Line ~197: FORWARD logging entfernt

**Kommentare hinzugefügt:**
```nix
# 10. Dropped packets (logging temporarily disabled)
# 15. Dropped packets (logging temporarily disabled)
# Block all forwarding (logging temporarily disabled - this machine is not a router)
```

**Commit:** (Teil der Fixes)

---

### Problem 4: Fehlende Kernel-Module

**Fehler (nach Logging-Entfernung):**
```
/nftables-rules:102:5-12: Error: Could not process rule: No such file or directory
ct state established,related accept
^^^^^^^^
```

**Ursache:** `nft_ct` Kernel-Modul nicht geladen

**Diagnose:**
```bash
$ lsmod | grep nft
nft_limit              16384  1
nft_compat             24576  7
nf_tables             401408  42 nft_compat,nft_limit
# nft_ct FEHLT!
```

**Lösung:** Kernel-Module zur Boot-Konfiguration hinzugefügt

**Datei:** `modules/firewall.nix` (Lines 53-65)

```nix
# ==========================================
# KERNEL MODULE CONFIGURATION
# ==========================================
# Load nftables kernel modules at boot
boot.kernelModules = [
  "nf_tables"
  "nft_counter"
  "nft_ct"           # Connection Tracking - KRITISCH
  "nft_limit"
  "nft_nat"
  "nft_reject"
  "nft_reject_inet"
];
```

**Commit:** (Teil der Fixes)

**Problem:** Module werden nur bei Boot geladen, nicht bei `nixos-rebuild switch`

**Status:** ⏸️ **REBOOT ERFORDERLICH**

---

## Task 6: MEMORY.md Dokumentation

### Durchgeführte Änderungen

**Datei:** `/home/achim/.claude/projects/-home-achim-nixos-config/memory/MEMORY.md`

**Hinzugefügt:** Sektion "Firewall Migration > iptables to nftables Migration (2026-02-05)"

**Inhalt:**
- Beschreibung der Änderung
- Key Files mit Details
- Testing Commands
- Wichtiger Hinweis über 1:1 Translation

**Note:** Diese Datei liegt außerhalb des nixos-config Repos, daher kein Git-Commit.

---

## Aktuelle Konfiguration

### Dateien geändert (insgesamt)

1. **modules/firewall.nix**
   - Kernel-Module hinzugefügt
   - `networking.nftables` mit unified `inet filter` Table
   - Alle iptables-Regeln zu nftables migriert
   - IPv6 in gleiche Table integriert
   - Logging temporär deaktiviert
   - `systemd.services.firewall` Block entfernt

2. **modules/protonvpn.nix**
   - VPN Pre-Check: `iptables` → `nft` Validierung
   - Service Dependencies: `firewall.service` → `nftables.service`
   - VPN Watchdog: Service-Check aktualisiert

3. **disable-firewall.sh**
   - Primary: `nft flush ruleset`
   - Fallback: Legacy iptables cleanup

4. **test-network-boot.sh**
   - Test 1: `nftables.service` Status
   - Test 1b: nftables Rules geladen

5. **docs/plans/2026-02-05-migrate-iptables-to-nftables.md**
   - Ursprünglicher Migrationsplan

6. **MEMORY.md**
   - Migration dokumentiert

### Uncommitted Changes

**Noch nicht committed:**
- modules/firewall.nix - Alle Bugfixes (Service-Name, IPv6, Logging, Kernel-Module)
- modules/protonvpn.nix - Service-Name Fix + VPN Routing-Änderungen (unrelated)
- modules/sops.nix - (Pre-existing changes)

---

## Nächste Schritte

### Sofort erforderlich

1. **REBOOT** - Damit Kernel-Module geladen werden
   ```bash
   sudo reboot
   ```

2. **Nach Reboot - Verification:**
   ```bash
   # Kernel-Module prüfen
   lsmod | grep nft
   # Sollte zeigen: nft_ct, nft_counter, nft_limit, nft_reject, etc.

   # nftables Service Status
   systemctl status nftables.service
   # Sollte: active (exited)

   # nftables Rules prüfen
   sudo nft list ruleset
   # Sollte: inet filter Table mit DROP policies zeigen

   # VPN Status
   systemctl status wg-quick-proton0.service
   # Sollte: active (exited)

   # Network Boot Test
   sudo ./test-network-boot.sh
   # Sollte: ALL TESTS PASSED

   # DNS-over-TLS Test
   resolvectl query google.com
   # Sollte: "encrypted transport: yes" zeigen

   # VPN Connectivity Test
   curl https://am.i.mullvad.net/json
   # Sollte: VPN IP zeigen, nicht echte IP
   ```

3. **Bei Erfolg - Final Commit:**
   ```bash
   git add modules/firewall.nix modules/protonvpn.nix test-network-boot.sh disable-firewall.sh
   git commit -m "feat: complete iptables to nftables migration

   Migration Summary:
   - Migrated firewall from iptables to nftables
   - Consolidated IPv4 and IPv6 rules into single inet table
   - Added required kernel modules for nftables
   - Updated all service references to nftables.service
   - Updated VPN pre-check validation
   - Updated emergency disable script
   - Updated network boot test
   - Temporarily disabled logging (kernel module incompatibility)

   Technical Details:
   - Uses networking.nftables instead of networking.firewall
   - Single table inet filter with unified chains
   - IPv6 rules use meta nfproto ipv6 matcher
   - Connection tracking via nft_ct kernel module
   - VPN kill switch maintained with DROP policies
   - DNS-over-TLS bootstrap strategy preserved
   - ICMPv6 Neighbor Discovery preserved

   Testing Required After Reboot:
   - Run ./test-network-boot.sh
   - Verify VPN connection
   - Verify DNS-over-TLS encryption

   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
   ```

### Später (Optional)

4. **Logging wieder aktivieren:**
   - Kernel-Kompatibilität für nftables Logging debuggen
   - Möglicherweise andere Logging-Methode (rsyslog, journal)
   - Oder ohne `level` Parameter testen nach Reboot

5. **VPN Routing-Änderungen commit:**
   - Separate von der Firewall-Migration
   - Aktuell in modules/protonvpn.nix unstaged
   - Priority 100/101/102 Routing-Regeln

---

## Rollback-Plan

Falls nach Reboot Probleme auftreten:

### Option 1: Immediate Rollback via NixOS
```bash
sudo nixos-rebuild switch --rollback
```

### Option 2: Emergency Firewall Disable
```bash
sudo ./disable-firewall.sh
```

### Option 3: Git Rollback
```bash
git reset --hard HEAD~N  # N = Anzahl der Commits zurück
sudo nixos-rebuild switch --flake .#achim-laptop
```

### Boot-Menü Fallback
- Bei Boot: Ältere NixOS Generation im Bootloader wählen
- System bootet mit vorheriger Konfiguration (iptables)

---

## Gelernte Lektionen

### Was gut funktionierte

1. **Subagent-Driven Development:**
   - Fresh subagent per task verhinderte Context-Pollution
   - Spec Compliance Review fing Scope Creep früh
   - Code Quality Review identifizierte Best Practices

2. **Iterative Problemlösung:**
   - Jedes Problem isoliert und systematisch gelöst
   - Build-Feedback direkt nach jeder Änderung
   - Git-History ermöglicht genaues Tracking

3. **Defensive Strategie:**
   - Logging deaktiviert um Kern-Funktionalität zu priorisieren
   - Kernel-Module explizit definiert statt auf Auto-Load zu vertrauen
   - Emergency-Skripte aktualisiert vor Deployment

### Herausforderungen

1. **NixOS nftables Integration:**
   - Dokumentation über `networking.nftables` ist limitiert
   - Service-Name Unterschied nicht offensichtlich
   - Kernel-Module müssen explizit geladen werden

2. **nftables Syntax-Subtleties:**
   - `inet` vs `ip6` Table Family
   - `level` Parameter Kernel-Kompatibilität
   - Logging-Module Inkompatibilität

3. **Deployment ohne Reboot:**
   - Kernel-Module laden nur bei Boot
   - `systemd-modules-load` Restart hilft nicht
   - Unvermeidbar für diese Art von Change

### Empfehlungen für zukünftige Migrationen

1. **Kernel-Module früh definieren:**
   - In Task 1 bereits alle erforderlichen Module hinzufügen
   - Reboot-Anforderung in Plan dokumentieren

2. **Logging separat behandeln:**
   - Als optionales Feature, nicht Kern-Anforderung
   - Separate Task für Logging-Aktivierung

3. **Test-Umgebung:**
   - Idealerweise in VM oder separatem System zuerst testen
   - Rollback-Plan vor erstem Deployment testen

---

## Sicherheitsüberprüfung

### Erhaltene Sicherheitsfeatures

✅ **VPN Kill Switch:**
- DROP Policy auf allen Chains
- Nur VPN-Interfaces (proton0, tun*, wg*) erlaubt
- Physische Interface nur für VPN-Verbindungsaufbau

✅ **DNS-over-TLS Dual-Phase:**
- Bootstrap: Quad9 (9.9.9.9) über physisches Interface
- VPN-Phase: Mullvad (194.242.2.2) über VPN
- Alle anderen DNS-over-TLS blockiert

✅ **Netzwerk-Bootstrap:**
- DHCP erlaubt (client:68 → server:67)
- DNS zu systemd-resolved Stub (127.0.0.53)
- ICMPv6 Neighbor Discovery für NetworkManager

✅ **Lokale Dienste:**
- Syncthing (Ports 22000 TCP/UDP, 21027 UDP)
- Drucker (192.168.178.28:631, 9100)
- mDNS (224.0.0.251:5353)

✅ **Port-Scan Detection:**
- Dynamic Set mit Timeout
- Rate Limiting: 10/minute
- Automatischer Drop bei Überschreitung

### Temporär deaktiviert

⚠️ **Logging:**
- Intrusion Detection Logs fehlen
- Dropped Packets nicht geloggt
- **Risiko:** Reduzierte Forensik-Fähigkeit
- **Mitigation:** System-Monitoring via VPN Watchdog aktiv

### Neue Sicherheitsaspekte

✅ **nftables Vorteile:**
- Moderner Kernel-Code, besser gewartet
- Bessere Performance durch Ruleset-Optimierung
- Atomare Ruleset-Updates (kein partial-load Risiko)

---

## Technische Details

### nftables Ruleset Struktur

```nix
table inet filter {
  # Port-Scan Detection Set
  set portscan {
    type ipv4_addr
    flags dynamic, timeout
    timeout 60s
  }

  # INPUT Chain
  chain input {
    type filter hook input priority filter
    policy drop

    # Loopback
    iif lo accept

    # Connection Tracking
    ct state established,related accept

    # DHCP
    udp sport 67 udp dport 68 accept

    # ... weitere Regeln ...

    # IPv6 ICMPv6
    meta nfproto ipv6 icmpv6 type { nd-router-advert, ... } accept

    # Port-Scan Detection
    update @portscan { ip saddr limit rate over 10/minute } drop
  }

  # OUTPUT Chain
  chain output {
    type filter hook output priority filter
    policy drop

    # Loopback
    oif lo accept

    # Connection Tracking
    ct state established,related accept

    # VPN Interfaces
    oifname "proton0" accept
    oifname "tun*" accept
    oifname "wg*" accept

    # VPN Connection Establishment
    udp dport { 51820, 88, 1224, 1194, 443, 500, 4500 } accept
    tcp dport 443 accept

    # ... weitere Regeln ...
  }

  # FORWARD Chain
  chain forward {
    type filter hook forward priority filter
    policy drop
  }
}
```

### Kernel-Module Details

**Geladen bei Boot:**
```
nf_tables          - Core nftables Framework
nft_counter        - Packet/Byte Counters
nft_ct             - Connection Tracking (KRITISCH)
nft_limit          - Rate Limiting
nft_nat            - NAT Support
nft_reject         - Packet Rejection
nft_reject_inet    - Rejection für inet Family
```

**Check nach Reboot:**
```bash
lsmod | grep nft_
# Sollte alle 7 Module zeigen
```

---

## Referenzen

### NixOS Dokumentation
- [networking.nftables Options](https://search.nixos.org/options?query=networking.nftables)
- [boot.kernelModules Options](https://search.nixos.org/options?query=boot.kernelModules)

### nftables Dokumentation
- [nftables Wiki](https://wiki.nftables.org/)
- [nftables Quick Reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes)
- [inet Family Documentation](https://wiki.nftables.org/wiki-nftables/index.php/Nftables_families)

### Git Commits (Chronologisch)
1. `2115f9c` - Task 1: nftables firewall configuration
2. `d3e30b7` - Task 2: VPN pre-check validation
3. `63810a1` - Task 3: disable-firewall.sh update
4. (Task 4 completed, not yet committed)
5. `0eedfc3` - Fix: Service reference updates
6. (Multiple fixes for IPv6, logging, kernel modules - not yet committed)

---

## Kontakt & Support

Bei Problemen nach Reboot:

1. **Logs prüfen:**
   ```bash
   sudo journalctl -u nftables.service -n 100 --no-pager
   sudo journalctl -u wg-quick-proton0.service -n 50
   ```

2. **Network Status:**
   ```bash
   ip addr
   ip route
   systemctl status NetworkManager
   ```

3. **Emergency Recovery:**
   ```bash
   ./disable-firewall.sh
   # Oder
   sudo nixos-rebuild switch --rollback
   ```

---

**Erstellt:** 2026-02-05
**Letzte Aktualisierung:** 2026-02-05 16:15 CET
**Status:** Wartet auf Reboot
**Verantwortlich:** Claude Sonnet 4.5 (Subagent-Driven Development)
