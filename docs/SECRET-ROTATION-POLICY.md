# Secret Rotation Policy

## Overview

This document defines the rotation schedule for all secrets managed via sops-nix in this NixOS configuration. Regular rotation reduces the window of exposure if a secret is compromised.

## Rotation Schedule

### Critical Secrets (Every 90 Days)

**API Keys:**
- Anthropic API Key (`anthropic/api_key`)
- GitHub API Token (`github/api_token`)
- Miniflux API Key (`miniflux/api_key`)

**Rationale:** API keys are used programmatically and may be logged/cached. Regular rotation limits exposure from log retention.

**Rotation Process:**
1. Generate new key in provider's dashboard
2. Update sops secret: `sops modules/secrets/secrets.yaml`
3. Test service with new key
4. Revoke old key in provider's dashboard
5. Rebuild system: `sudo nixos-rebuild switch`

---

### High-Priority Secrets (Every 6 Months)

**Network Credentials:**
- WiFi PSK (`wifi/eduroam/password`, `wifi/home/psk`)
- ProtonVPN Private Key (`protonvpn/private_key`)

**Rationale:** Network credentials have high impact if compromised (network access) but changing them affects stability.

**Rotation Process:**
1. WiFi: Change router/AP password, update sops, rebuild
2. VPN: Regenerate WireGuard keypair in ProtonVPN dashboard, update sops

---

### Standard Secrets (Every Year)

**SSH Keys:**
- Hetzner VPS SSH Key (`ssh/hetzner_vps/key`)

**Email Passwords:**
- Posteo Account Password (`email/posteo/password`)

**Rationale:** Less frequently accessed, lower risk of exposure, more disruptive to change.

**Rotation Process:**
1. SSH: Generate new ed25519 key, add to server, test, remove old, update sops
2. Email: Change password in provider, update sops, update Thunderbird

---

### Never Rotate (Unless Compromised)

**Encryption Keys:**
- Age Key (`/var/lib/sops-nix/key.txt`)

**Rationale:** Age key is used to decrypt all other secrets. Rotating requires re-encrypting entire secrets file.

**Emergency Rotation Process (if compromised):**
1. Generate new age key: `age-keygen -o new-key.txt`
2. Re-key all secrets: `sops --rotate --age $(cat new-key.txt | age-keygen -y) modules/secrets/secrets.yaml`
3. Replace key: `sudo mv new-key.txt /var/lib/sops-nix/key.txt`
4. Rebuild: `sudo nixos-rebuild switch`

---

## Rotation Reminders

### Manual Tracking

Create calendar reminders:
- **Quarterly:** Check API keys (every 90 days)
- **Bi-annually:** Check WiFi/VPN (every 6 months)
- **Annually:** Check SSH/Email (every year)

### Automated Checks (Future Enhancement)

```nix
# TODO: Implement automated rotation reminders
systemd.services.secret-rotation-reminder = {
  description = "Secret Rotation Reminder";
  script = ''
    # Check last rotation dates and notify if overdue
    # Send desktop notification or email
  '';
};

systemd.timers.secret-rotation-reminder = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "monthly";
  };
};
```

---

## Audit Trail

### Last Rotation Dates

Track in `docs/SECRET-ROTATION-LOG.md`:

```markdown
| Secret | Last Rotated | Next Due | Rotated By |
|--------|--------------|----------|------------|
| Anthropic API | 2026-02-05 | 2026-05-06 | user |
| GitHub Token | - | OVERDUE | - |
| WiFi PSK | - | - | - |
```

---

## Security Best Practices

1. **Never commit plaintext secrets** - Always use sops encryption
2. **Rotate after suspected compromise** - Don't wait for schedule
3. **Test before revoking old secret** - Ensure new secret works
4. **Document rotation in log** - Track compliance with policy
5. **Use unique secrets per service** - Don't reuse credentials

---

## Related Documentation

- Age Key Storage: See `modules/sops.nix`
- Secret Management: See `docs/SECRETS.md`
- Incident Response: See `docs/INCIDENT-RESPONSE.md` (TODO)

---

## Policy Version

- **Version:** 1.0
- **Effective Date:** 2026-02-05
- **Last Updated:** 2026-02-05
- **Owner:** user
