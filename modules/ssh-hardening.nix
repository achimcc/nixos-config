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
      UsePAM = true;                       # PAM-Stack nutzen

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
    # allowUsers = [ id.username ];

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

  # ==========================================
  # SSH-CLIENT: KEIN systemd-ssh-proxy-INCLUDE
  # ==========================================

  # NixOS schreibt sonst in /etc/ssh/ssh_config eine Zeile
  #
  #   Include <systemd>/lib/systemd/ssh_config.d/20-systemd-ssh-proxy.conf
  #
  # und diese eingebundene Datei gehoert root im Store. OpenSSH prueft bei
  # JEDER per `Include` geholten Datei den Eigentuemer (root oder der eigene
  # Nutzer, readconf.c) — die Systemdatei selbst prueft es nicht, nur das
  # Include.
  #
  # Im bwrap-Sandkasten von VSCodium (siehe home.nix, ~/.local/bin/codium)
  # geht diese Pruefung nicht auf: Der unprivilegierte User-Namespace bildet
  # genau eine UID ab, die eigene. root erscheint drinnen als 65534
  # (`nobody`) — weder root noch der eigene Nutzer. Ergebnis im integrierten
  # Terminal:
  #
  #   Bad owner or permissions on <systemd>/…/20-systemd-ssh-proxy.conf
  #
  # Danach steht der ganze ssh-Aufruf, also auch `git pull`. Gemessen: ohne
  # dieses Include liest ssh im Sandkasten wieder alles, inklusive der
  # Nutzer-Config (`identityfile ~/.ssh/id_ed25519`, `identitiesonly yes`).
  #
  # DER PREIS: `ssh unix/<pfad>` und `ssh vsock/<cid>` funktionieren nicht
  # mehr — der Weg zu lokalen VMs/Containern ueber systemd-vmspawn und
  # machinectl. Hier laeuft nichts davon; die Server haengen an Tailscale und
  # werden ueber Namen und IP erreicht.
  #
  # DIE ANDERE MOEGLICHKEIT WAERE bwrap setuid: dann entfaellt der
  # User-Namespace und root bleibt root, was die Ursache bei der Wurzel packt
  # und JEDE root-Datei im Sandkasten wieder lesbar macht. Dafuer haengt ein
  # SUID-Binary am Sandbox-Start. Bewusst nicht gemacht — hier steht eine
  # ungenutzte Bequemlichkeit gegen ein Privileg.
  programs.ssh.systemd-ssh-proxy.enable = false;
}
