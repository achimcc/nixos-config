# Secret Rotation Audit Log

Track all secret rotations to ensure compliance with rotation policy.

## API Keys (90-day rotation)

| Secret | Last Rotated | Next Due | Status | Rotated By | Notes |
|--------|--------------|----------|--------|------------|-------|
| Anthropic API Key | 2026-02-05 | 2026-05-06 | ✅ Current | <nutzer> | Initial setup |
| GitHub API Token | - | 2026-05-06 | ⚠️ TODO | - | Need to rotate |
| Miniflux API Key | - | 2026-05-06 | ⚠️ TODO | - | Need to rotate |

## Network Credentials (6-month rotation)

| Secret | Last Rotated | Next Due | Status | Rotated By | Notes |
|--------|--------------|----------|--------|------------|-------|
| WiFi Eduroam Password | - | 2026-08-05 | ⚠️ TODO | - | Need to set rotation baseline |
| WiFi Home PSK | - | 2026-08-05 | ⚠️ TODO | - | Need to set rotation baseline |
| ProtonVPN Private Key | - | 2026-08-05 | ⚠️ TODO | - | Need to set rotation baseline |

## Standard Secrets (Yearly rotation)

| Secret | Last Rotated | Next Due | Status | Rotated By | Notes |
|--------|--------------|----------|--------|------------|-------|
| Hetzner VPS SSH Key | - | 2027-02-05 | ⚠️ TODO | - | Need to set rotation baseline |
| Posteo Email Password | - | 2027-02-05 | ⚠️ TODO | - | Need to set rotation baseline |

## Encryption Keys (Only on compromise)

| Secret | Created | Last Rotated | Status | Notes |
|--------|---------|--------------|--------|-------|
| Age Key | - | Never | ✅ Secure | Stored in `/var/lib/sops-nix/key.txt` |
| LUKS-Passphrase Root + Swap | - | 2026-09-13 | 🔒 Rotated | Rückfall zu FIDO2 (Nitrokey 3), eine Passphrase für beide Geräte |

---

## Rotation Template

When rotating a secret, add entry below:

**Date:** YYYY-MM-DD
**Secret:** [secret name]
**Rotated By:** [your name]
**Reason:** Scheduled / Compromised / Security Audit
**Old Value Hash:** [sha256 of old secret for verification]
**New Value Hash:** [sha256 of new secret]
**Services Restarted:** [list of affected services]
**Verification:** ✅ Passed / ❌ Failed
**Notes:** [any additional context]

---

## Rotationen

**Date:** 2026-09-13
**Secret:** LUKS-Passphrase Root-Partition (`fcef0557…`) und Swap-Partition (`f8e58c55…`)
**Rotated By:** <nutzer>
**Reason:** Security Audit – Wechsel auf Nitrokey 3, Rotation bei der Gelegenheit
**Old/New Value Hash:** bewusst nicht protokolliert
**Services Restarted:** keine
**Verification:** ✅ Neue Slots per `cryptsetup open --test-passphrase --key-slot` geprüft (Root 1,
Swap 3), danach alte Slots 0 entfernt. `luksDump`: Root 1 = Passphrase, 2 = FIDO2; Swap 1 = TPM2,
3 = Passphrase. Neustart-Test ohne Stick steht aus (Aufgabe 7b im Nitrokey-Plan).
**Notes:** Acht EFF-Wörter nur aus `a`–`x`, getrennt durch Leerzeichen (≈101 Bit), damit die
Passphrase auf US- und DE-Layout gleich getippt wird. Ein versehentlich angelegter Swap-Slot mit
bekanntem Inhalt (Befehlstext) wurde am selben Tag wieder entfernt.

---

## Legend

- ✅ Current - Within rotation window
- ⚠️ TODO - Needs rotation soon
- 🔴 OVERDUE - Past rotation deadline
- 🔒 Rotated - Recently rotated

---

**Last Updated:** 2026-09-13
