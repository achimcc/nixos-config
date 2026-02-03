# SSH Server Hardening (DEAKTIVIERT)
# Diese Konfiguration ist vorbereitet für zukünftige SSH-Aktivierung
# SSH ist aktuell komplett deaktiviert (kein Server läuft)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SSH SERVER - DEAKTIVIERT
  # ==========================================

  services.openssh = {
    enable = false;  # WICHTIG: SSH ist deaktiviert!

    # Falls SSH aktiviert wird, gelten folgende Härtungs-Einstellungen:
    settings = {
      # Authentifizierung
      PasswordAuthentication = false;      # Nur Keys erlaubt
      PermitRootLogin = "no";              # Root-Login verboten
      ChallengeResponseAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = false;
      UsePAM = true;                       # PAM für FIDO2-Keys

      # Forwarding & Features
      X11Forwarding = false;               # X11 deaktiviert
      AllowAgentForwarding = false;        # Agent-Forwarding deaktiviert
      AllowTcpForwarding = false;          # TCP-Forwarding deaktiviert
      PermitTunnel = false;                # Tunnel deaktiviert
      GatewayPorts = "no";                 # Keine Remote Port-Forwards

      # Protocol Hardening
      Protocol = 2;                        # SSH Protocol 2 (v1 ist unsicher)
      MaxAuthTries = 3;                    # Max 3 Auth-Versuche
      MaxSessions = 2;                     # Max 2 Sessions pro Verbindung
      ClientAliveInterval = 300;           # 5 Minuten Idle-Timeout
      ClientAliveCountMax = 2;             # 2x Idle-Check, dann Disconnect

      # Crypto Hardening
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];

      # Logging
      LogLevel = "VERBOSE";  # Detaillierte Logs für Fail2ban
    };

    # SFTP deaktiviert (wenn SSH läuft, nur Shell-Zugriff)
    allowSFTP = false;

    # Nur explizit erlaubte User (anpassen bei Aktivierung)
    # allowUsers = [ "user" ];

    # SSH auf non-standard Port (Security durch Obscurity + weniger Scans)
    # ports = [ 22022 ];  # Auskommentiert, Standard-Port 22
  };

  # ==========================================
  # FAIL2BAN SSH-JAIL
  # ==========================================

  # Fail2ban ist bereits in security.nix aktiviert
  # Falls SSH aktiviert wird, automatisch SSH-Jail aktiv
  services.fail2ban.jails = {
    sshd = ''
      enabled = true
      port = ssh
      filter = sshd
      maxretry = 3
      findtime = 600
      bantime = 3600
    '';
  };
}
