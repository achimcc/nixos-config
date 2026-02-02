# TODO: Add Admin Email to SOPS Secrets

## Action Required

You need to manually add the admin email address to the encrypted secrets file.

## Steps

1. Open the secrets file for editing:
   ```bash
   sops /home/user/nixos-config/secrets/secrets.yaml
   ```

2. Add the following entry under the `system:` section:
   ```yaml
   system:
       admin-email: "user@posteo.de"
   ```

3. Save and close the editor

4. Verify the secret is accessible:
   ```bash
   sudo cat /run/secrets/system/admin-email
   ```

5. After verification, rebuild the system:
   ```bash
   sudo nixos-rebuild switch --flake /home/user/nixos-config#nixos
   ```

6. Delete this TODO file after completion

## Context

This email address is used for:
- Logwatch daily security reports
- AIDE file integrity alerts
- Critical security event notifications
- System health monitoring alerts
